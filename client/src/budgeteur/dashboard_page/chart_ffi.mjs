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
        this.#root.replaceChildren(...draw(Plot, spec.months, width));
      }
    },
  );
}

const fontSize = '12px';
const income = '#4f46e5';
const expenses = '#9ca3af';

/// Months in the order the server sent them, labelled by their short name.
function monthAxis(months) {
  return {
    domain: months.map((month) => month.label),
    tickFormat: (label) => label.slice(0, 3),
    label: null,
  };
}

/// The month to date is drawn faded, as it is partial.
const opacity = (month) => (month.complete ? 1 : 0.45);

/// Income bars above the axis and expense bars below it, with net income as a
/// line, and a legend above them.
function cashFlow(Plot, months, width) {
  const chart = Plot.plot({
    width,
    height: 260,
    marginLeft: 64,
    style: { fontSize },
    x: monthAxis(months),
    y: { grid: true, label: null, tickFormat: '$,~s' },
    color: {
      domain: ['Income', 'Expenses', 'Net income'],
      range: [income, expenses, 'currentColor'],
    },
    marks: [
      Plot.barY(months, {
        x: 'label',
        y: 'income',
        fill: () => 'Income',
        fillOpacity: opacity,
        tip: true,
        title: (month) => `${month.label}\nIncome ${money(month.income)}`,
      }),
      Plot.barY(months, {
        x: 'label',
        y: (month) => -month.expenses,
        fill: () => 'Expenses',
        fillOpacity: opacity,
        tip: true,
        title: (month) => `${month.label}\nExpenses ${money(month.expenses)}`,
      }),
      Plot.ruleY([0]),
      Plot.lineY(months, {
        x: 'label',
        y: 'netIncome',
        stroke: () => 'Net income',
      }),
      ...dots(Plot, months, 'netIncome', 'currentColor', 'Net income'),
    ],
  });
  return [chart.legend('color', { style: { fontSize } }), chart];
}

/// Net worth at each month's closing date. Months with no known balance are
/// gaps.
function netWorth(Plot, months, width) {
  return [Plot.plot({
    width,
    height: 260,
    marginLeft: 64,
    style: { fontSize },
    x: monthAxis(months),
    y: { grid: true, label: null, tickFormat: '$,~s' },
    marks: [
      Plot.lineY(months, { x: 'label', y: 'netWorth', stroke: income }),
      ...dots(Plot, months, 'netWorth', income, 'Net worth'),
    ],
  })];
}

/// A dot per month with its figure on hover: filled for complete months and
/// hollow for the month to date.
function dots(Plot, months, field, color, name) {
  const options = (complete) => ({
    x: 'label',
    y: field,
    filter: (month) => month.complete === complete,
    stroke: color,
    fill: complete ? color : 'white',
    tip: true,
    title: (month) =>
      `${month.label}${complete ? '' : ' to date'}\n${name} ${
        money(month[field])
      }`,
  });
  return [Plot.dot(months, options(true)), Plot.dot(months, options(false))];
}

const currency = new Intl.NumberFormat('en-NZ', {
  style: 'currency',
  currency: 'NZD',
});

const money = (amount) => currency.format(amount);
