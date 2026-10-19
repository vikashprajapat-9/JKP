@IsTest
private class CommissionFormatTest {

    @IsTest
    static void datesAreWrittenOut() {
        Date sample = Date.newInstance(2026, 9, 1);
        String written = CommissionFormat.dateText(sample);
        System.assertEquals(Datetime.newInstance(2026, 9, 1).format('dd MMM yyyy'), written, 'Day, short month and year, like 01 Sep 2026');
        System.assert(written.startsWith('01 ') && written.endsWith(' 2026'), 'The day has two digits and the year closes the date: ' + written);
        System.assertEquals(null, CommissionFormat.dateText(null), 'No date, no text');
        System.assertEquals(written, CommissionFormat.text(sample), 'A date reads the same as a value of any kind');

        // Compared with the same format call, so that the time zone of the running user does not matter
        Datetime moment = Datetime.newInstance(2026, 9, 1, 14, 5, 0);
        System.assertEquals(moment.format('dd MMM yyyy HH:mm'), CommissionFormat.text(moment), 'A moment carries its time');
    }

    @IsTest
    static void numbersStayPlain() {
        System.assertEquals('80', CommissionFormat.numberText(80.00), 'Zeros after the point are dropped');
        System.assertEquals('12.5', CommissionFormat.numberText(12.50), 'What is left of the decimals stays');
        System.assertEquals('1000', CommissionFormat.numberText(1000.00), 'No separator and no exponent');
        System.assertEquals('0', CommissionFormat.numberText(0), 'Zero is a number');
        System.assertEquals('0', CommissionFormat.numberText(0.00), 'With decimals as well');
        System.assertEquals(null, CommissionFormat.numberText(null), 'No number, no text');
        Decimal rate = 12.50;
        System.assertEquals('12.5', CommissionFormat.text(rate), 'A number reads the same as a value of any kind');
    }

    @IsTest
    static void otherValuesReadAsText() {
        System.assertEquals(null, CommissionFormat.text(null), 'Nothing stays nothing');
        System.assertEquals(CommissionFormat.COMMISSION_COMMON_YES, CommissionFormat.text(true), 'True is Yes');
        System.assertEquals(CommissionFormat.COMMISSION_COMMON_NO, CommissionFormat.text(false), 'False is No');
        System.assertEquals(null, CommissionFormat.text(''), 'An empty text is nothing');
        System.assertEquals(null, CommissionFormat.text('   '), 'Neither is a text of spaces');
        System.assertEquals('Configuration Period', CommissionFormat.text('Configuration Period'), 'A text stays as it is');
    }
}