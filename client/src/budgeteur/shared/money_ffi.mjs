const cache = new Map();

export function formatCurrency(amount, locale, currency) {
  const key = `${locale}|${currency}`;
  let numberFormat = cache.get(key);

  if (!numberFormat) {
    numberFormat = new Intl.NumberFormat(locale, { style: "currency", currency });
    cache.set(key, numberFormat);
  }

  return numberFormat.format(amount);
}
