// The parts of Observable Plot the charts use. `chart_ffi.mjs` imports this
// module on first draw, so the bundler can drop the rest of Plot from the
// chunk it loads.
export { barY, dot, lineY, plot, ruleY } from '@observablehq/plot';
