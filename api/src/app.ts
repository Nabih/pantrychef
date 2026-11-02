import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import compress from "@fastify/compress";
import type { Pool } from "pg";
import { ApiError, registerRoutes } from "./routes.js";

export interface BuildAppOptions {
  pool: Pool;
  corsOrigin: true | string[];
  logger?: boolean;
}

export function buildApp(options: BuildAppOptions): FastifyInstance {
  const app = Fastify({
    logger: options.logger ?? false,
    bodyLimit: 32 * 1024,
    trustProxy: true,
  });

  app.register(cors, {
    origin: options.corsOrigin === true ? true : options.corsOrigin,
    methods: ["GET", "POST"],
    maxAge: 86_400,
  });

  app.register(compress, { global: true, threshold: 1024 });

  registerRoutes(app, options.pool);

  app.setNotFoundHandler((_request, reply) => {
    reply.code(404).send({ error: "not_found", message: "Unknown route." });
  });

  app.setErrorHandler((error: FastifyError, request, reply) => {
    if (error.validation) {
      return reply.code(400).send({
        error: "invalid_request",
        message: error.message,
      });
    }

    if (error instanceof ApiError) {
      return reply
        .code(error.statusCode)
        .send({ error: error.code, message: error.message });
    }

    request.log.error(error);
    return reply.code(500).send({
      error: "internal_error",
      message: "Something went wrong.",
    });
  });

  return app;
}
