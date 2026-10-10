const cache = new Map();

export function formatInteger(value, locale) {
  let numberFormat = cache.get(locale);

  if (!numberFormat) {
    numberFormat = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 });
    cache.set(locale, numberFormat);
  }

  return numberFormat.format(value);
}
