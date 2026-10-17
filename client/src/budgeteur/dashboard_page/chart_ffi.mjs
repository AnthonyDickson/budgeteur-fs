// The `<dashboard-chart>` custom element behind `chart.view`. The page sets
// its `spec` property to the chart's kind and the server's monthly figures;
// the element draws them with Observable Plot into its shadow root and redraws
// whenever `spec` changes. Plot is imported on first draw, so its code loads
// only when a chart is shown. The element only maps figures to marks: it never
// sums, stacks, or accumulates them. See decision 15 in docs/dashboard.md.
export function registerChart() {
  if (customElements.get('dashboard-chart')) {
    return;
  }

  customElements.define(
    'dashboard-chart',
    class extends HTMLElement {
      #spec = null;
      #root = this.attachShadow({ mode: 'open' });

      get spec() {
        return this.#spec;
      }

      set spec(spec) {
        this.#spec = spec;
        this.#draw();
      }

      connectedCallback() {
        this.#draw();
      }

      async #draw() {
        const spec = this.#spec;
        if (!spec || !this.isConnected) {
          return;
        }

        const Plot = await import('./chart_plot.mjs');

        // A newer spec arrived while Plot was loading; its draw wins.
        if (spec !== this.#spec) {
          return;
        }

        const width = this.clientWidth || 640;
        const draw = spec.kind === 'cashFlow' ? cashFlow : netWorth;
        this.#root.replaceChildren(
          plotBackground(),
          draw(Plot, spec.months, width),
        );
      }
    },
  );
}

const fontSize = '12px';
// Colours are colour roles from the page's stylesheet, which inherit into the
// shadow root, so a drawn chart follows a change of mode. See decision 10 in
// docs/styling.md.
const accent = 'var(--color-primary)';
const surface = 'var(--color-surface)';

/// Plot fills tooltips with `--plot-background`, which it sets to white in a
/// `:where` rule, so this rule wins.
function plotBackground() {
  const style = document.createElement('style');
  style.textContent = `svg { --plot-background: ${surface}; }`;
  return style;
}

// The plot's side margins; the left one fits the y axis's labels.
const marginLeft = 64;
const marginRight = 20;
// The width a month needs for its short name with space either side.
const labelWidth = 32;

/// Months in the order the server sent them, labelled by their short name.
/// Where the months are too narrow for every name, as on a phone, every second
/// or third month is named, counting back from the latest, and every month
/// keeps its tick.
function monthAxis(months, width) {
  const labels = months.map((month) => month.label);
  const band = (width - marginLeft - marginRight) / labels.length;
  const step = Math.ceil(labelWidth / band);
  return {
    domain: labels,
    tickFormat: (label) =>
      (labels.length - 1 - labels.indexOf(label)) % step === 0
        ? label.slice(0, 3)
        : '',
    label: null,
  };
}

/// The month to date is drawn faded, as it is partial.
const opacity = (month) => (month.complete ? 1 : 0.45);

/// Net income per month as bars: above the axis for a month that saved and
/// below it for one that did not. A bar's tooltip also has the month's income
/// and expenses, since the table with them starts collapsed.
function cashFlow(Plot, months, width) {
  return Plot.plot({
    width,
    height: 260,
    marginLeft,
    marginRight,
    style: { fontSize },
    x: monthAxis(months, width),
    y: { grid: true, label: null, tickFormat: '$,~s' },
    marks: [
      Plot.barY(months, {
        x: 'label',
        y: 'netIncome',
        fill: accent,
        fillOpacity: opacity,
        tip: true,
        title: (month) =>
          [
            `${month.label}${month.complete ? '' : ' to date'}`,
            `Income ${money(month.income)}`,
            `Expenses ${money(month.expenses)}`,
            `Net income ${money(month.netIncome)}`,
          ].join('\n'),
      }),
      Plot.ruleY([0]),
    ],
  });
}

/// Net worth at each month's closing date. Months with no known balance are
/// gaps.
function netWorth(Plot, months, width) {
  return Plot.plot({
    width,
    height: 260,
    marginLeft,
    marginRight,
    style: { fontSize },
    x: monthAxis(months, width),
    // Unlike the bars, the line does not start at zero, so its lowest and
    // highest points would sit on the axis and the top edge without an inset.
    y: { grid: true, label: null, tickFormat: '$,~s', inset: 12 },
    // The dots' fill is a colour per month, used as is.
    color: { type: 'identity' },
    marks: [
      Plot.lineY(months, { x: 'label', y: 'netWorth', stroke: accent }),
      ...dots(Plot, months, 'netWorth', accent, 'Net worth'),
    ],
  });
}

/// A dot per month with its figure on hover: filled for complete months and
/// hollow for the month to date. One mark, so one tip: each mark's tip follows
/// the pointer on its own, and a tap would show a tip per mark.
function dots(Plot, months, field, color, name) {
  return [
    Plot.dot(months, {
      x: 'label',
      y: field,
      stroke: color,
      fill: (month) => (month.complete ? color : surface),
      tip: true,
      title: (month) =>
        `${month.label}${month.complete ? '' : ' to date'}\n${name} ${
          money(month[field])
        }`,
    }),
  ];
}

const currency = new Intl.NumberFormat('en-NZ', {
  style: 'currency',
  currency: 'NZD',
});

const money = (amount) => currency.format(amount);
