@IsTest
private class PartnerEmailSenderTest {

    private static List<Messaging.SingleEmailMessage> emails() {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ 'partner@example.com' });
        email.setSubject('Test');
        email.setPlainTextBody('Test');
        email.setSaveAsActivity(false);
        return new List<Messaging.SingleEmailMessage>{ email };
    }

    // An id that looks like an Organization-Wide Email Address but does not exist
    private static Id unknownSender() {
        return Id.valueOf(OrgWideEmailAddress.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    @IsTest
    static void withoutSenderTheRunningUserSends() {
        PartnerEmailSender.setting = new Partner_Portal_Setting__mdt();
        List<Messaging.SingleEmailMessage> emails = emails();

        Test.startTest();
        System.assertEquals(null, PartnerEmailSender.senderId(), 'No sender is set up');
        List<Messaging.SendEmailResult> results = PartnerEmailSender.send(emails);
        Integer sends = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(null, emails[0].getOrgWideEmailAddressId(), 'The email is left as it is');
        System.assertEquals(1, results.size());
        System.assert(results[0].isSuccess(), 'The email goes out as the running user');
        System.assertEquals(1, sends);
    }

    @IsTest
    static void unknownAddressIsIgnored() {
        PartnerEmailSender.setting = new Partner_Portal_Setting__mdt(Email_Sender_Address__c = 'no.such.sender@example.com');
        List<Messaging.SingleEmailMessage> emails = emails();

        Test.startTest();
        PartnerEmailSender.apply(emails);
        Test.stopTest();

        System.assertEquals(null, PartnerEmailSender.senderId(), 'An address that is not an Organization-Wide Email Address is not used');
        System.assertEquals(null, emails[0].getOrgWideEmailAddressId());
    }

    @IsTest
    static void senderIsPutOnEveryEmail() {
        PartnerEmailSender.resolved = true;
        PartnerEmailSender.resolvedSender = unknownSender();
        List<Messaging.SingleEmailMessage> emails = emails();
        emails.addAll(emails());

        Test.startTest();
        PartnerEmailSender.apply(emails);
        Test.stopTest();

        System.assertEquals(PartnerEmailSender.resolvedSender, emails[0].getOrgWideEmailAddressId());
        System.assertEquals(PartnerEmailSender.resolvedSender, emails[1].getOrgWideEmailAddressId());
    }

    @IsTest
    static void emailTheSenderCannotSendGoesOutAsTheRunningUser() {
        PartnerEmailSender.resolved = true;
        PartnerEmailSender.resolvedSender = unknownSender();
        List<Messaging.SingleEmailMessage> emails = emails();

        Test.startTest();
        List<Messaging.SendEmailResult> results = PartnerEmailSender.send(emails);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].isSuccess(), 'The partner still gets the email: ' + results[0].getErrors());
        System.assertEquals(null, emails[0].getOrgWideEmailAddressId(), 'It was sent as the running user');
    }

    // [[Tokens]] get their values; in HTML a value is never read as markup
    @IsTest
    static void fillsWhatATemplateLeavesToApex() {
        Map<String, String> values = new Map<String, String>{ '[[Customer]]' => 'A & B <Buyers>', '[[Visit Time]]' => null };

        System.assertEquals('Visit with A & B <Buyers> at .', PartnerEmailSender.fill('Visit with [[Customer]] at [[Visit Time]].', values));
        System.assertEquals('<b>A &amp; B &lt;Buyers&gt;</b> and A &amp; B &lt;Buyers&gt;',
            PartnerEmailSender.fillHtml('<b>[[Customer]]</b> and [[Customer]]', values));
        System.assertEquals('', PartnerEmailSender.fill(null, values));
        System.assertEquals('', PartnerEmailSender.fillHtml(null, values));
    }

    // With a reason, [[Reason]] becomes it; without one, the part kept for it goes
    @IsTest
    static void putsTheReasonInItsPlace() {
        String html = '<body><p>No.</p><!--reason--><p>Reason: [[Reason]]</p><!-- /Reason --><p>Bye</p></body>';
        String text = 'No.\n\nReason: [[Reason]]\n\nBye';

        System.assertEquals('<body><p>No.</p><!--reason--><p>Reason: Too &lt;late&gt;<br>Sorry</p><!-- /Reason --><p>Bye</p></body>',
            PartnerEmailSender.htmlWithReason(html, 'Too <late>\nSorry', 'Line: Too <late>'));
        System.assertEquals('<body><p>No.</p><p>Bye</p></body>', PartnerEmailSender.htmlWithReason(html, null, null));
        System.assertEquals('No.\n\nReason: Too <late>\n\nBye', PartnerEmailSender.textWithReason(text, 'Too <late>', 'Line: Too <late>'));
        System.assertEquals('No.\n\nBye', PartnerEmailSender.textWithReason(text, null, null));
    }

    // A template without a place for the reason gets it as its last line
    @IsTest
    static void addsTheReasonToATemplateWithoutAPlaceForIt() {
        System.assertEquals('<body><p>No.</p><p>Line: A &amp; B</p></body>',
            PartnerEmailSender.htmlWithReason('<body><p>No.</p></body>', 'A & B', 'Line: A & B'));
        System.assertEquals('<p>No.</p><p>A &amp; B</p>', PartnerEmailSender.htmlWithReason('<p>No.</p>', 'A & B', null));
        System.assertEquals('No.\n\nLine: A & B', PartnerEmailSender.textWithReason('No.', 'A & B', 'Line: A & B'));
        System.assertEquals('No.\n\nA & B', PartnerEmailSender.textWithReason('No.', 'A & B', ''));
        System.assertEquals('No.', PartnerEmailSender.textWithReason('No.', null, null));
        System.assertEquals('', PartnerEmailSender.htmlWithReason(null, null, null));
    }
}