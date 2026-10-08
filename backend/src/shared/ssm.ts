import { GetParameterCommand, type SSMClient } from "@aws-sdk/client-ssm";

/** Reads a SecureString once per container; a failed read is retried on the next call. */
export function ssmValue(ssm: SSMClient, name: string): () => Promise<string> {
  let value: Promise<string> | undefined;
  return () => {
    value ??= ssm
      .send(new GetParameterCommand({ Name: name, WithDecryption: true }))
      .then((res) => {
        const v = res.Parameter?.Value;
        if (!v) throw new Error(`SSM parameter ${name} is empty`);
        return v;
      })
      .catch((err: unknown) => {
        value = undefined;
        throw err;
      });
    return value;
  };
}

export function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`missing environment variable ${name}`);
  return value;
}
