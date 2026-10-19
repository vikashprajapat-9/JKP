// The email to the applicant of a channel partner registration that JKP rejected (the onboarding chart: "Approved by CP
// Manager? No: Rejection notification"). The flow PartnerPortalApprovalandRejection calls it when Onboarding Status
// becomes Rejected. The email goes out afterwards, in a transaction of its own (Queueable): an email sent from inside the
// rejection's save was lost. The wording and design are the Rejection Email Template of the Partner Registration Setting,
// and the approver's comment is shown in it as the reason.
public without sharing class PartnerRegistrationRejection implements Queueable {
    // Messages this class shows or sends
    @TestVisible private static final String PARTNER_REGISTRATION_REJECTION_REASON = 'Reason: {0}';


    private final List<Id> accountIds;

    // How many rejection emails the last run sent (for tests)
    @TestVisible
    private static Integer emailsSent = 0;

    public PartnerRegistrationRejection(List<Id> accountIds) {
        this.accountIds = accountIds;
    }

    @InvocableMethod(label='Email Rejected Partner Registration' description='Emails the applicant of each rejected channel partner registration, once the rejection is saved')
    public static void emailRejected(List<Id> accountIds) {
        List<Id> rejected = new List<Id>();
        for (Id accountId : accountIds) {
            if (accountId != null) {
                rejected.add(accountId);
            }
        }
        if (!rejected.isEmpty()) {
            System.enqueueJob(new PartnerRegistrationRejection(rejected));
        }
    }

    public void execute(QueueableContext context) {
        Partner_Registration_Setting__mdt setting = Partner_Registration_Setting__mdt.getInstance('Default');
        String templateName = setting == null ? null : setting.Rejection_Email_Template__c;
        if (String.isBlank(templateName)) {
            return;
        }
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName.trim() WITH SYSTEM_MODE LIMIT 1];
        if (templates.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Rejection Email Template not found: ' + templateName);
            return;
        }

        // The approver's comment of the latest rejection of each registration
        Map<Id, String> reasons = new Map<Id, String>();
        for (ProcessInstanceStep step : [
            SELECT ProcessInstance.TargetObjectId, Comments FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId IN :accountIds AND StepStatus = 'Rejected'
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC
        ]) {
            if (!reasons.containsKey(step.ProcessInstance.TargetObjectId)) {
                reasons.put(step.ProcessInstance.TargetObjectId, step.Comments);
            }
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Account applicant : [
            SELECT Id, Email__c, (SELECT Id, Email FROM Contacts ORDER BY CreatedDate ASC LIMIT 1)
            FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE
        ]) {
            Contact person = applicant.Contacts.isEmpty() ? null : applicant.Contacts[0];
            String address = String.isNotBlank(applicant.Email__c) ? applicant.Email__c : (person == null ? null : person.Email);
            if (String.isBlank(address)) {
                continue;
            }
            Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templates[0].Id, person == null ? null : person.Id, applicant.Id);
            String reason = reasons.get(applicant.Id);
            reason = String.isBlank(reason) || reason.trim().equalsIgnoreCase('Rejected') ? null : reason.trim();
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ address });
            email.setSubject(rendered.getSubject());
            email.setPlainTextBody(textWithReason(rendered.getPlainTextBody(), reason));
            if (String.isNotBlank(rendered.getHtmlBody())) {
                email.setHtmlBody(htmlWithReason(rendered.getHtmlBody(), reason));
            }
            email.setSaveAsActivity(false);
            emails.add(email);
        }
        if (emails.isEmpty()) {
            return;
        }
        for (Messaging.SendEmailResult result : PartnerEmailSender.send(emails)) {
            if (result.isSuccess()) {
                emailsSent++;
            } else {
                System.debug(LoggingLevel.ERROR, 'Rejection email not sent: ' + result.getErrors());
            }
        }
    }

    // ---------- the reason in the template ----------

    // In the template, [[Reason]] stands for the approver's comment. Without a comment, the HTML version loses the part
    // between <!--reason--> and <!--/reason-->, and the text version the line that holds [[Reason]] (PartnerEmailSender).
    @TestVisible
    private static final String REASON_TOKEN = PartnerEmailSender.REASON_TOKEN;

    @TestVisible
    private static String htmlWithReason(String html, String reason) {
        return PartnerEmailSender.htmlWithReason(html, reason, lineOf(reason));
    }

    @TestVisible
    private static String textWithReason(String text, String reason) {
        return PartnerEmailSender.textWithReason(text, reason, lineOf(reason));
    }

    // The reason as a line of its own, for a template without a place for it
    private static String lineOf(String reason) {
        return reason == null ? null : String.format(PARTNER_REGISTRATION_REJECTION_REASON, new List<Object>{ reason });
    }
}