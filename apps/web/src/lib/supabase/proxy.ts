import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { getSupabasePublicEnv } from "@/lib/supabase/env";

const AUTH_ROUTES = new Set(["/login", "/signup", "/forgot-password"]);

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({
    request,
  });

  const { url, publishableKey } = getSupabasePublicEnv();

  const supabase = createServerClient(url, publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value);
        });
        supabaseResponse = NextResponse.next({
          request,
        });
        cookiesToSet.forEach(({ name, value, options }) => {
          supabaseResponse.cookies.set(name, value, options);
        });
      },
    },
  });

  // Refresh the auth session and validate the JWT.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;
  const isAuthRoute = AUTH_ROUTES.has(pathname);
  const isResetPassword = pathname === "/reset-password";
  const isAuthCallback = pathname.startsWith("/auth/");
  const isProtected =
    pathname === "/" || pathname.startsWith("/dashboard") || isResetPassword;

  if (!user && isProtected && !isAuthCallback) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = isResetPassword ? "/forgot-password" : "/login";
    if (!isResetPassword) {
      redirectUrl.searchParams.set(
        "next",
        pathname === "/" ? "/dashboard" : pathname,
      );
    }
    return NextResponse.redirect(redirectUrl);
  }

  if (user && (isAuthRoute || pathname === "/")) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/dashboard";
    redirectUrl.search = "";
    return NextResponse.redirect(redirectUrl);
  }

  return supabaseResponse;
}
