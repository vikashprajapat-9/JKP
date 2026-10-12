// How a value reads in the messages of Commission Setup: a date, a number, yes or no.
// Kept in one class so that the rules, the triggers and the services all write a value the same way.
public without sharing class CommissionFormat {

    // 01 Sep 2026
    public static String dateText(Date value) {
        return value == null ? null : Datetime.newInstance(value.year(), value.month(), value.day()).format('dd MMM yyyy');
    }

    // 80 for 80.00, 12.5 for 12.50
    public static String numberText(Decimal value) {
        if (value == null) {
            return null;
        }
        return value == 0 ? '0' : value.stripTrailingZeros().toPlainString();
    }

    public static String text(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean) {
            return ((Boolean) value) ? System.Label.Commission_Common_Yes : System.Label.Commission_Common_No;
        }
        if (value instanceof Date) {
            return dateText((Date) value);
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).format('dd MMM yyyy HH:mm');
        }
        if (value instanceof Decimal) {
            return numberText((Decimal) value);
        }
        String asText = String.valueOf(value);
        return String.isBlank(asText) ? null : asText;
    }
}