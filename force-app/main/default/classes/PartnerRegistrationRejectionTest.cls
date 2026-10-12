// The email to the applicant of a rejected channel partner registration (PartnerRegistrationRejection)
@isTest
private class PartnerRegistrationRejectionTest {

    private static Account registration(String email) {
        Account applicant = new Account(Name = 'Rejection Test Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Email__c = email, Onboarding_Status__c = 'Pending', Portal_Registration_User__c = true, Document_Id__c = 'test-folder');
        insert applicant;
        insert new Contact(AccountId = applicant.Id, FirstName = 'Kamal', LastName = 'Perera', Email = email);
        return applicant;
    }

    // Rejecting the registration (Onboarding Status Rejected, as the approval sets it) emails the applicant afterwards
    @isTest
    static void emailsTheApplicantOnceTheRejectionIsSaved() {
        Account applicant = registration('rejected@rejection-test.example.com');

        Test.startTest();
        update new Account(Id = applicant.Id, Onboarding_Status__c = 'Rejected');
        Test.stopTest();

        System.assertEquals(1, PartnerRegistrationRejection.emailsSent, 'The rejection email');
    }

    // No account, nothing queued; an account without any email address gets none
    @isTest
    static void sendsNothingWithoutAnAddress() {
        Account applicant = registration('no-address@rejection-test.example.com');
        update new Account(Id = applicant.Id, Email__c = null);
        delete [SELECT Id FROM Contact WHERE AccountId = :applicant.Id];

        Test.startTest();
        PartnerRegistrationRejection.emailRejected(new List<Id>{ null });
        System.enqueueJob(new PartnerRegistrationRejection(new List<Id>{ applicant.Id }));
        Test.stopTest();

        System.assertEquals(0, PartnerRegistrationRejection.emailsSent);
    }

    // ---------- the reason in the template ----------

    private static final String HTML_TEMPLATE = '<html><body><p>Dear Kamal,</p><!--reason--><table><tr><td>REASON</td><td>[[Reason]]</td></tr></table><!--/reason--><p>Thanks</p></body></html>';
    private static final String TEXT_TEMPLATE = 'Dear Kamal,\n\nWe are unable to approve it.\n\nReason: [[Reason]]\n\nIf you have any questions, contact us.';

    @isTest
    static void theReasonIsShownWhereTheTemplateHasItsPlace() {
        String html = PartnerRegistrationRejection.htmlWithReason(HTML_TEMPLATE, 'Document is not clear');
        System.assert(html.contains('<td>Document is not clear</td>'), html);
        System.assert(!html.contains('[[Reason]]'), html);

        String text = PartnerRegistrationRejection.textWithReason(TEXT_TEMPLATE, 'Document is not clear');
        System.assert(text.contains('\n\nReason: Document is not clear\n\nIf you have any questions'), text);
    }

    // Whatever the approver typed is shown as text, never read as markup, and keeps its line breaks
    @isTest
    static void theReasonIsNeverReadAsMarkup() {
        String html = PartnerRegistrationRejection.htmlWithReason(HTML_TEMPLATE, 'NIC <b>unclear</b> & old\nSecond line');
        System.assert(html.contains('NIC &lt;b&gt;unclear&lt;/b&gt; &amp; old<br>Second line'), html);
        System.assert(!html.contains('<b>unclear</b>'), html);
    }

    @isTest
    static void withoutAReasonItsPartIsLeftOut() {
        String html = PartnerRegistrationRejection.htmlWithReason(HTML_TEMPLATE, null);
        System.assertEquals('<html><body><p>Dear Kamal,</p><p>Thanks</p></body></html>', html);

        String text = PartnerRegistrationRejection.textWithReason(TEXT_TEMPLATE, null);
        System.assertEquals('Dear Kamal,\n\nWe are unable to approve it.\n\nIf you have any questions, contact us.', text);
    }

    // A template that has no place for the reason still tells it, at the end
    @isTest
    static void aTemplateWithoutAPlaceGetsTheReasonAtTheEnd() {
        String reasonLine = String.format(Label.Partner_Registration_Rejection_Reason, new List<Object>{ 'Document is not clear' });

        String html = PartnerRegistrationRejection.htmlWithReason('<html><body><p>Dear Kamal,</p></body></html>', 'Document is not clear');
        System.assertEquals('<html><body><p>Dear Kamal,</p><p>' + reasonLine.escapeHtml4() + '</p></body></html>', html);
        System.assertEquals('<p>Dear Kamal,</p>', PartnerRegistrationRejection.htmlWithReason('<p>Dear Kamal,</p>', null));

        System.assertEquals('Dear Kamal,\n\n' + reasonLine, PartnerRegistrationRejection.textWithReason('Dear Kamal,', 'Document is not clear'));
        System.assertEquals('Dear Kamal,', PartnerRegistrationRejection.textWithReason('Dear Kamal,', null));
        System.assertEquals('', PartnerRegistrationRejection.textWithReason(null, null));
    }

    // The markers are found whatever their spacing or capitals
    @isTest
    static void theMarkersMayBeWrittenLoosely() {
        String html = '<p>Dear Kamal,</p><!-- Reason --><div>REASON</div>\n<div>[[Reason]]</div><!-- /REASON --><p>Thanks</p>';
        System.assertEquals('<p>Dear Kamal,</p><p>Thanks</p>', PartnerRegistrationRejection.htmlWithReason(html, null));
        // A token left outside the markers is at least emptied
        System.assertEquals('<p>Reason: </p>', PartnerRegistrationRejection.htmlWithReason('<p>Reason: [[Reason]]</p>', null));
    }

    // The template the settings name still has the places this class relies on (it can be edited in Setup)
    @isTest
    static void theTemplateOfTheSettingsKeepsItsPlaceForTheReason() {
        Partner_Registration_Setting__mdt setting = Partner_Registration_Setting__mdt.getInstance('Default');
        List<EmailTemplate> templates = setting == null || String.isBlank(setting.Rejection_Email_Template__c) ? new List<EmailTemplate>() :
            [SELECT Id FROM EmailTemplate WHERE DeveloperName = :setting.Rejection_Email_Template__c.trim() LIMIT 1];
        if (templates.isEmpty()) {
            return;
        }
        Account applicant = registration('template@rejection-test.example.com');
        Contact person = [SELECT Id FROM Contact WHERE AccountId = :applicant.Id LIMIT 1];

        Test.startTest();
        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templates[0].Id, person.Id, applicant.Id);
        Test.stopTest();

        String token = PartnerRegistrationRejection.REASON_TOKEN;
        String html = rendered.getHtmlBody();
        if (html != null && html.contains(token)) {
            String without = PartnerRegistrationRejection.htmlWithReason(html, null);
            System.assert(!without.contains(token), 'Without a reason no token is left');
            System.assert(without.length() < html.length() - token.length(),
                'In the HTML version [[Reason]] is between <!--reason--> and <!--/reason-->, so its whole part is left out');
            System.assert(PartnerRegistrationRejection.htmlWithReason(html, 'NIC <b>unclear</b>').contains('NIC &lt;b&gt;unclear&lt;/b&gt;'), 'With a reason it is shown as text');
        }
        String text = rendered.getPlainTextBody();
        if (text != null && text.contains(token)) {
            String without = PartnerRegistrationRejection.textWithReason(text, null);
            System.assert(!without.contains(token), 'Without a reason no token is left in the text version');
            System.assert(!without.contains('\n\n\n'), 'and no gap where its line was: ' + without);
            System.assert(PartnerRegistrationRejection.textWithReason(text, 'NIC unclear').contains('NIC unclear'));
        }
    }
}