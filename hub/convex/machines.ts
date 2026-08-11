import { v } from "convex/values";
import { internalQuery } from "./_generated/server";
import { fingerprintValidator } from "./schema";
import { similarityScore, type Fingerprint } from "./lib/similarity";
import { mergeMachineCandidates } from "./lib/machines";
import { validateSimilarMachinesRequest, MAX_MACHINES_SCORED, capScoredCandidates } from "./lib/validation";

export const similarMachines = internalQuery({
  args: {
    fingerprint: fingerprintValidator,
    limit: v.optional(v.number()),
  },
  returns: v.array(
    v.object({
      machine_id: v.id("machines"),
      similarity: v.number(),
      machine_label: v.optional(v.string()),
      gpu_vendor: v.string(),
      display: v.string(),
      profiles: v.array(v.string()),
    }),
  ),
  handler: async (ctx, args) => {
    const limit = validateSimilarMachinesRequest({
      fingerprint: args.fingerprint as Fingerprint,
      limit: args.limit,
    });
    const byVendor = await ctx.db
      .query("machines")
      .withIndex("by_gpu_vendor", (q) =>
        q.eq("fingerprint.gpu_vendor", args.fingerprint.gpu_vendor),
      )
      .order("desc")
      .take(MAX_MACHINES_SCORED);

    const byDisplayTier = await ctx.db
      .query("machines")
      .withIndex("by_display_tier", (q) =>
        q.eq("fingerprint.display_tier", args.fingerprint.display_tier),
      )
      .order("desc")
      .take(MAX_MACHINES_SCORED);

    const candidates = capScoredCandidates(
      mergeMachineCandidates(byVendor, byDisplayTier),
      MAX_MACHINES_SCORED,
    );

    return candidates
      .map((machine) => ({
        machine_id: machine._id,
        similarity: similarityScore(
          args.fingerprint as Fingerprint,
          machine.fingerprint as Fingerprint,
        ),
        machine_label: machine.machineLabel,
        gpu_vendor: machine.fingerprint.gpu_vendor,
        display: machine.fingerprint.display ?? "",
        profiles: machine.fingerprint.profiles,
      }))
      .filter((row) => row.similarity > 0)
      .sort((a, b) => b.similarity - a.similarity)
      .slice(0, limit);
  },
});
