/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as appleAuth from "../appleAuth.js";
import type * as auth from "../auth.js";
import type * as classifications from "../classifications.js";
import type * as classifyWaste from "../classifyWaste.js";
import type * as dropoff from "../dropoff.js";
import type * as facilities from "../facilities.js";
import type * as facilitiesCache from "../facilitiesCache.js";
import type * as files from "../files.js";
import type * as friends from "../friends.js";
import type * as henrysPipeline from "../henrysPipeline.js";
import type * as http from "../http.js";
import type * as impactTable from "../impactTable.js";
import type * as map from "../map.js";
import type * as metrics from "../metrics.js";
import type * as migrate from "../migrate.js";
import type * as profiles from "../profiles.js";
import type * as ragCatalog from "../ragCatalog.js";
import type * as ragConstants from "../ragConstants.js";
import type * as ragPipeline from "../ragPipeline.js";
import type * as sage from "../sage.js";
import type * as weeklyInsights from "../weeklyInsights.js";
import type * as weeklyInsightsAction from "../weeklyInsightsAction.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  appleAuth: typeof appleAuth;
  auth: typeof auth;
  classifications: typeof classifications;
  classifyWaste: typeof classifyWaste;
  dropoff: typeof dropoff;
  facilities: typeof facilities;
  facilitiesCache: typeof facilitiesCache;
  files: typeof files;
  friends: typeof friends;
  henrysPipeline: typeof henrysPipeline;
  http: typeof http;
  impactTable: typeof impactTable;
  map: typeof map;
  metrics: typeof metrics;
  migrate: typeof migrate;
  profiles: typeof profiles;
  ragCatalog: typeof ragCatalog;
  ragConstants: typeof ragConstants;
  ragPipeline: typeof ragPipeline;
  sage: typeof sage;
  weeklyInsights: typeof weeklyInsights;
  weeklyInsightsAction: typeof weeklyInsightsAction;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
