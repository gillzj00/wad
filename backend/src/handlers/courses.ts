// Routes: GET /v1/courses?q=<search>, GET /v1/courses/{courseId}
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { GetParameterCommand, SSMClient } from "@aws-sdk/client-ssm";
import { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import { DynamoCourseCache } from "../services/courses/cache.js";
import { CourseService, QueryTooShortError } from "../services/courses/courseService.js";
import { GolfCourseApiProvider } from "../services/courses/golfCourseApi.js";
import { ProviderError } from "../services/courses/provider.js";
import { error, json } from "../shared/http.js";

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
        default:
          return error(404, "route_not_found", `no route for ${event.routeKey}`);
      }
    } catch (err) {
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
