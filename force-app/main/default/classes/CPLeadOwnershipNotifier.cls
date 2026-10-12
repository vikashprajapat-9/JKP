// The email to a channel partner whose lead went to another channel partner: the other CP completed the first
// successful site visit with the same customer for the same project (the Lead Management chart, CP -> CP; see
// LeadLogicController.applyFirstSiteVisitRule). It goes to the lead's owner, the portal user who submitted it, in a
// transaction of its own after the site visit is saved. The wording is the CP Lead Ownership Email Template of the
// Partner Portal Setting.
public without sharing class CPLeadOwnershipNotifier implements Queueable {

    private final Set<Id> leadIds;

    // How many emails the last run sent (for tests)
    @TestVisible
    private static Integer emailsSent = 0;

    public CPLeadOwnershipNotifier(Set<Id> leadIds) {
        this.leadIds = leadIds;
    }

    // Emails the owners of these leads once the current transaction is saved (now, when no job can be queued any more)
    public static void notifyLater(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new CPLeadOwnershipNotifier(new Set<Id>(leadIds)));
        } else {
            send(leadIds);
        }
    }

    public void execute(QueueableContext context) {
        send(leadIds);
    }

    private static void send(Set<Id> leadIds) {
        Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance('Default');
        String templateName = setting == null ? null : setting.CP_Lead_Ownership_Email_Template__c;
        if (String.isBlank(templateName)) {
            return;
        }
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName.trim() WITH SYSTEM_MODE LIMIT 1];
        if (templates.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'CP Lead Ownership Email Template not found: ' + templateName);
            return;
        }
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Lead lost : [
            SELECT Id, OwnerId FROM Lead
            WHERE Id IN :leadIds AND Owner.Type = 'User' AND Owner.IsActive = true
            WITH SYSTEM_MODE
        ]) {
            Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templates[0].Id, lost.Id, null);
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(lost.OwnerId);
            email.setSubject(rendered.getSubject());
            email.setPlainTextBody(rendered.getPlainTextBody());
            // The template in the John Keells design has both versions; a text-only one sends as before
            if (String.isNotBlank(rendered.getHtmlBody())) {
                email.setHtmlBody(rendered.getHtmlBody());
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
                System.debug(LoggingLevel.ERROR, 'CP lead ownership email not sent: ' + result.getErrors());
            }
        }
    }
}