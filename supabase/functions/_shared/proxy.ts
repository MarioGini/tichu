import { corsHeaders } from "./cors.ts";

function jsonResponse(status: number, payload: unknown): Response {
    return new Response(JSON.stringify(payload), {
        status,
        headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
        },
    });
}

function readAction(body: unknown): string | null {
    if (!body || typeof body !== "object" || Array.isArray(body)) {
        return null;
    }

    const action = (body as Record<string, unknown>).action;
    if (typeof action !== "string" || action.length === 0) {
        return null;
    }
    return action;
}

function decodeBase64Url(value: string): string {
    const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
    const padding = "=".repeat((4 - (normalized.length % 4)) % 4);
    return atob(`${normalized}${padding}`);
}

function readAuthUserId(request: Request): string | null {
    const authorization = request.headers.get("authorization");
    if (!authorization || !authorization.startsWith("Bearer ")) {
        return null;
    }

    const token = authorization.slice("Bearer ".length).trim();
    const parts = token.split(".");
    if (parts.length < 2) {
        return null;
    }

    try {
        const payload = JSON.parse(decodeBase64Url(parts[1]));
        return typeof payload.sub === "string" && payload.sub.length > 0
            ? payload.sub
            : null;
    } catch {
        return null;
    }
}

export function createProxyHandler() {
    return async (request: Request): Promise<Response> => {
        if (request.method === "OPTIONS") {
            return new Response("ok", { headers: corsHeaders });
        }

        if (request.method !== "POST") {
            return jsonResponse(405, { error: "Only POST requests are supported." });
        }

        let parsedBody: unknown;
        try {
            parsedBody = await request.json();
        } catch {
            return jsonResponse(400, { error: "Request body must be valid JSON." });
        }

        const action = readAction(parsedBody);
        if (!action) {
            return jsonResponse(400, {
                error: "Missing action in Supabase function request body.",
            });
        }

        const { action: _ignoredAction, ...forwardBody } = parsedBody as Record<string, unknown>;
        const authUserId = readAuthUserId(request);
        if (!authUserId) {
            return jsonResponse(401, {
                error: "Missing authenticated Supabase user. Sign in before invoking multiplayer functions.",
            });
        }

        const authorityUrl = Deno.env.get("TICHU_AUTHORITY_URL");
        if (!authorityUrl) {
            return jsonResponse(500, {
                error: "Missing TICHU_AUTHORITY_URL for Supabase function proxy.",
            });
        }

        const targetUrl = new URL(
            action,
            authorityUrl.endsWith("/") ? authorityUrl : `${authorityUrl}/`,
        );
        const upstreamHeaders = new Headers({
            "content-type": request.headers.get("content-type") ?? "application/json",
        });

        const proxySecret = Deno.env.get("TICHU_AUTHORITY_PROXY_SECRET");
        if (proxySecret) {
            upstreamHeaders.set("x-tichu-proxy-secret", proxySecret);
        }
        upstreamHeaders.set("x-tichu-auth-user-id", authUserId);

        try {
            const upstream = await fetch(targetUrl, {
                method: "POST",
                headers: upstreamHeaders,
                body: JSON.stringify(forwardBody),
            });
            const responseText = await upstream.text();
            return new Response(responseText, {
                status: upstream.status,
                headers: {
                    ...corsHeaders,
                    "Content-Type": upstream.headers.get("content-type") ?? "application/json",
                },
            });
        } catch (error) {
            return jsonResponse(502, {
                error: `Failed to reach authority server for ${action}: ${error}`,
            });
        }
    };
}