// Routes: GET /v1/courses?q=<search>, GET /v1/courses/{courseId},
// POST /v1/courses, POST /v1/courses/{courseId}/corrections
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { GetParameterCommand, SSMClient } from "@aws-sdk/client-ssm";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import { DynamoCourseCache } from "../services/courses/cache.js";
import { CourseNotFoundError, CourseService, QueryTooShortError } from "../services/courses/courseService.js";
import { GolfCourseApiProvider } from "../services/courses/golfCourseApi.js";
import { ProviderError } from "../services/courses/provider.js";
import { validateCorrection, validateManualCourse, ValidationError } from "../services/courses/validation.js";
import { error, json } from "../shared/http.js";

class UnauthorizedError extends Error {}
class InvalidBodyError extends Error {}

/** The caller's user id: the `sub` claim set by the API Gateway JWT authorizer. */
function callerId(event: APIGatewayProxyEventV2): string {
  const context = event.requestContext as { authorizer?: { jwt?: { claims?: Record<string, unknown> } } } | undefined;
  const sub = context?.authorizer?.jwt?.claims?.sub;
  if (typeof sub !== "string" || sub === "") throw new UnauthorizedError();
  return sub;
}

function parseBody(event: APIGatewayProxyEventV2): unknown {
  if (!event.body) throw new InvalidBodyError();
  const text = event.isBase64Encoded ? Buffer.from(event.body, "base64").toString("utf8") : event.body;
  try {
    return JSON.parse(text);
  } catch {
    throw new InvalidBodyError();
  }
}

export function createHandler(service: CourseService) {
  return async (event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> => {
    try {
      switch (event.routeKey) {
        case "GET /v1/courses": {
          const courses = await service.search(event.queryStringParameters?.q ?? "");
          return json(200, { courses });
        }
        case "GET /v1/courses/{courseId}": {
          const course = await service.getCourse(event.pathParameters?.courseId ?? "");
          return course ? json(200, { course }) : error(404, "course_not_found", "no course with that id");
        }
        case "POST /v1/courses": {
          const userId = callerId(event);
          const course = await service.createManualCourse(validateManualCourse(parseBody(event)), userId);
          return json(201, { course });
        }
        case "POST /v1/courses/{courseId}/corrections": {
          const userId = callerId(event);
          const input = validateCorrection(parseBody(event));
          const correction = await service.submitCorrection(event.pathParameters?.courseId ?? "", input, userId);
          return json(201, { correction });
        }
        default:
          return error(404, "route_not_found", `no route for ${event.routeKey}`);
      }
    } catch (err) {
      if (err instanceof UnauthorizedError) return error(401, "unauthorized", "a signed-in user is required");
      if (err instanceof InvalidBodyError) return error(400, "invalid_body", "request body must be valid JSON");
      if (err instanceof ValidationError) return json(400, { error: { code: "validation_failed", message: err.message, field: err.field } });
      if (err instanceof CourseNotFoundError) return error(404, "course_not_found", "no course with that id");
      if (err instanceof QueryTooShortError) return error(400, "query_too_short", err.message);
      if (err instanceof ProviderError) {
        console.error("course provider error", err.kind, err.message);
        if (err.kind === "rate_limited") return error(503, "course_provider_rate_limited", "course search is temporarily unavailable; try again later");
        return error(502, "course_provider_unavailable", "course data is temporarily unavailable");
      }
      throw err;
    }
  };
}

let apiKey: Promise<string> | undefined;
function loadApiKey(ssm: SSMClient, name: string): Promise<string> {
  apiKey ??= ssm
    .send(new GetParameterCommand({ Name: name, WithDecryption: true }))
    .then((res) => {
      const value = res.Parameter?.Value;
      if (!value) throw new Error(`SSM parameter ${name} is empty`);
      return value;
    })
    .catch((err: unknown) => {
      apiKey = undefined;
      throw err;
    });
  return apiKey;
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`missing environment variable ${name}`);
  return value;
}

let handlerInstance: ReturnType<typeof createHandler> | undefined;

export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  if (!handlerInstance) {
    const ssm = new SSMClient({});
    const keyParam = requireEnv("GOLFCOURSEAPI_KEY_PARAM");
    const provider = new GolfCourseApiProvider(() => loadApiKey(ssm, keyParam));
    const cache = new DynamoCourseCache(DynamoDBDocumentClient.from(new DynamoDBClient({})), requireEnv("TABLE_NAME"));
    handlerInstance = createHandler(new CourseService(provider, cache));
  }
  return handlerInstance(event);
}
