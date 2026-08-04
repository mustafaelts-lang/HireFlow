import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { getSupabasePublicEnv } from "@/lib/supabase/env";
import { ACTIVE_TENANT_COOKIE } from "@/lib/tenancy/roles";

const AUTH_ROUTES = new Set(["/login", "/signup", "/forgot-password"]);

function isAppRoute(pathname: string) {
  return (
    pathname.startsWith("/dashboard") ||
    pathname.startsWith("/settings") ||
    pathname === "/"
  );
}

function isOnboardingRoute(pathname: string) {
  return pathname.startsWith("/onboarding");
}

function isInviteRoute(pathname: string) {
  return pathname.startsWith("/invites");
}

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

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;
  const isAuthRoute = AUTH_ROUTES.has(pathname);
  const isResetPassword = pathname === "/reset-password";
  const isAuthCallback = pathname.startsWith("/auth/");
  const needsAuth =
    isAppRoute(pathname) ||
    isOnboardingRoute(pathname) ||
    isInviteRoute(pathname) ||
    isResetPassword;

  if (!user && needsAuth && !isAuthCallback) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = isResetPassword ? "/forgot-password" : "/login";
    if (!isResetPassword) {
      redirectUrl.searchParams.set("next", pathname);
    }
    return NextResponse.redirect(redirectUrl);
  }

  if (!user) {
    return supabaseResponse;
  }

  const { count } = await supabase
    .from("tenant_memberships")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .eq("status", "active");

  const hasTenant = (count ?? 0) > 0;

  if (isAuthRoute || pathname === "/") {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = hasTenant
      ? "/dashboard"
      : "/onboarding/organization";
    redirectUrl.search = "";
    return NextResponse.redirect(redirectUrl);
  }

  if (!hasTenant && isAppRoute(pathname)) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/onboarding/organization";
    redirectUrl.search = "";
    return NextResponse.redirect(redirectUrl);
  }

  if (hasTenant && isOnboardingRoute(pathname)) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/dashboard";
    redirectUrl.search = "";
    return NextResponse.redirect(redirectUrl);
  }

  if (hasTenant) {
    const cookieTenantId = request.cookies.get(ACTIVE_TENANT_COOKIE)?.value;
    if (!cookieTenantId) {
      const { data: membership } = await supabase
        .from("tenant_memberships")
        .select("tenant_id")
        .eq("user_id", user.id)
        .eq("status", "active")
        .limit(1)
        .maybeSingle();

      if (membership?.tenant_id) {
        supabaseResponse.cookies.set(
          ACTIVE_TENANT_COOKIE,
          membership.tenant_id,
          {
            httpOnly: true,
            sameSite: "lax",
            secure: process.env.NODE_ENV === "production",
            path: "/",
            maxAge: 60 * 60 * 24 * 365,
          },
        );
      }
    }
  }

  return supabaseResponse;
}
