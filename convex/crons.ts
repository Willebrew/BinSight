import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.interval(
  "rebuild weekly leaderboard",
  { hours: 1 },
  internal.leaderboard.rebuildCurrentWeek,
);

export default crons;
