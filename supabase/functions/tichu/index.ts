import { createProxyHandler } from "../_shared/proxy.ts";

Deno.serve(createProxyHandler());