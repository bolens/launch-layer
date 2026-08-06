import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.interval(
  "clean expired operational records",
  { hours: 24 },
  internal.rate_limits.cleanupExpiredRecords,
  {},
);

export default crons;
