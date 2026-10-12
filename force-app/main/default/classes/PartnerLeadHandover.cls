// The "Site visit done & transition from agent to JKP team" lane of the Lead Nurturing chart. When a channel partner's
// lead reaches the Hand Over Lead Status of the Partner Portal Setting (Visited: the visit is completed, on the portal
// or in Salesforce), the JKP CP team takes it over:
//  - the lead goes to the JKP CP Executive (the CP Executive Username, else the partner account's owner);
//  - the CP Executive gets a task to take it over and convert it, and the CP Executive and the CP Manager are emailed
//    (Hand Over Email Template);
//  - the partner keeps seeing the lead, read-only, and can still upload the customer's documents
//    (partnerWebPortalLeadDocuments).
// When the lead is converted, its documents follow the customer: the new account and opportunity get them.
public without sharing class PartnerLeadHandover {

    // Tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance('Default');

    // The emails written (for tests: emails are not sent in tests)
    @TestVisible
    private static Integer emailsWritten = 0;

    // Before update: a partner's lead that reaches the hand-over stage goes to the JKP CP Executive
    public static void beforeUpdate(List<Lead> leads, Map<Id, Lead> oldLeads) {
        String stage = handOverStage();
        if (stage == null || oldLeads == null) {
            return;
        }
        List<Lead> reached = new List<Lead>();
        Set<Id> ownerIds = new Set<Id>();
        for (Lead record : leads) {
            Lead before = oldLeads.get(record.Id);
            if (before != null && record.Status == stage && before.Status != stage && record.Channel_Partner__c != null && !record.IsConverted) {
                reached.add(record);
                ownerIds.add(record.OwnerId);
            }
        }
        if (reached.isEmpty()) {
            return;
        }
        partnerWebPortalLeadEditController.loadOwners(ownerIds);
        Map<Id, Id> executiveByAccount = new Map<Id, Id>();
        for (Lead record : reached) {
            // Only a lead the partner still owns (JKP may own it already)
            if (!partnerWebPortalLeadEditController.isPartnerUser(record.OwnerId)) {
                continue;
            }
            if (!executiveByAccount.containsKey(record.Channel_Partner__c)) {
                List<Id> team = PartnerSiteVisitService.cpTeamOf(record.Channel_Partner__c);
                executiveByAccount.put(record.Channel_Partner__c, team == null ? null : team[0]);
            }
            Id executive = executiveByAccount.get(record.Channel_Partner__c);
            if (executive != null) {
                record.OwnerId = executive;
            } else {
                System.debug(LoggingLevel.ERROR, 'No JKP CP Executive to take over lead ' + record.Id);
            }
        }
    }

    // After update: the JKP CP team is told about the leads handed over, and a converted lead's documents follow the
    // customer
    public static void afterUpdate(List<Lead> leads, Map<Id, Lead> oldLeads) {
        if (oldLeads == null) {
            return;
        }
        String stage = handOverStage();
        List<Lead> handedOver = new List<Lead>();
        Set<Id> converted = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();
        for (Lead record : leads) {
            Lead before = oldLeads.get(record.Id);
            if (before == null) {
                continue;
            }
            if (record.IsConverted && !before.IsConverted) {
                converted.add(record.Id);
            }
            if (stage != null && record.Status == stage && before.Status != stage && record.Channel_Partner__c != null
                    && record.OwnerId != before.OwnerId) {
                handedOver.add(record);
                ownerIds.add(record.OwnerId);
                ownerIds.add(before.OwnerId);
            }
        }
        if (!handedOver.isEmpty()) {
            partnerWebPortalLeadEditController.loadOwners(ownerIds);
            List<Lead> toJkp = new List<Lead>();
            for (Lead record : handedOver) {
                // From the partner to a JKP user: the hand-over of beforeUpdate
                if (partnerWebPortalLeadEditController.isPartnerUser(oldLeads.get(record.Id).OwnerId)
                        && record.OwnerId.getSObjectType() == User.SObjectType && !partnerWebPortalLeadEditController.isPartnerUser(record.OwnerId)) {
                    toJkp.add(record);
                }
            }
            if (!toJkp.isEmpty()) {
                notifyTeam(toJkp);
            }
        }
        if (!converted.isEmpty()) {
            moveDocuments(converted);
        }
    }

    // A task for the CP Executive and an email to the CP Executive and the CP Manager. A notice that cannot be saved
    // or sent does not stop the lead's update.
    private static void notifyTeam(List<Lead> leads) {
        List<Lead> details = [
            SELECT Id, Name, OwnerId, Channel_Partner__c, Channel_Partner__r.Name, Project__r.Name FROM Lead WHERE Id IN :leads WITH SYSTEM_MODE
        ];
        List<Task> tasks = new List<Task>();
        for (Lead record : details) {
            String partner = record.Channel_Partner__r == null ? '' : record.Channel_Partner__r.Name;
            String project = record.Project__r == null ? '' : record.Project__r.Name;
            tasks.add(new Task(
                OwnerId = record.OwnerId,
                WhoId = record.Id,
                Status = 'Not Started',
                Priority = 'High',
                ActivityDate = Date.today().addDays(1),
                Subject = String.format(Label.Partner_Lead_Hand_Over_Subject, new List<Object>{ record.Name }).left(255),
                Description = String.format(Label.Partner_Lead_Hand_Over_Text, new List<Object>{ partner, record.Name, project })
            ));
        }
        for (Database.SaveResult result : Database.insert(tasks, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Hand-over task not saved: ' + result.getErrors());
            }
        }
        emailTeam(details);
    }

    private static void emailTeam(List<Lead> leads) {
        String templateName = setting == null || String.isBlank(setting.Hand_Over_Email_Template__c) ? null : setting.Hand_Over_Email_Template__c.trim();
        if (templateName == null) {
            return;
        }
        try {
            List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName WITH SYSTEM_MODE LIMIT 1];
            if (templates.isEmpty()) {
                System.debug(LoggingLevel.ERROR, 'Hand Over Email Template not found: ' + templateName);
                return;
            }
            // The CP Manager of each partner account, copied
            Map<Id, Id> managerByAccount = new Map<Id, Id>();
            for (Lead record : leads) {
                if (!managerByAccount.containsKey(record.Channel_Partner__c)) {
                    List<Id> team = PartnerSiteVisitService.cpTeamOf(record.Channel_Partner__c);
                    managerByAccount.put(record.Channel_Partner__c, team == null ? null : team[1]);
                }
            }
            Map<Id, User> managers = new Map<Id, User>([
                SELECT Id, Email FROM User WHERE Id IN :managerByAccount.values() AND IsActive = true WITH SYSTEM_MODE
            ]);
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Lead record : leads) {
                // Rendered for the lead, sent to the CP Executive (never to the customer)
                Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templates[0].Id, record.Id, null);
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(record.OwnerId);
                User manager = managers.get(managerByAccount.get(record.Channel_Partner__c));
                if (manager != null && manager.Id != record.OwnerId && String.isNotBlank(manager.Email)) {
                    email.setCcAddresses(new List<String>{ manager.Email });
                }
                email.setSubject(rendered.getSubject());
                email.setPlainTextBody(rendered.getPlainTextBody());
                email.setSaveAsActivity(false);
                emails.add(email);
            }
            emailsWritten += emails.size();
            for (Messaging.SendEmailResult result : PartnerEmailSender.send(emails)) {
                if (!result.isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'Hand-over email not sent: ' + result.getErrors());
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Hand-over email not sent: ' + e.getMessage());
        }
    }

    // A converted lead's documents follow the customer: the new account and opportunity get them
    private static void moveDocuments(Set<Id> leadIds) {
        Map<Id, Lead> leads = new Map<Id, Lead>([
            SELECT Id, ConvertedAccountId, ConvertedOpportunityId FROM Lead WHERE Id IN :leadIds WITH SYSTEM_MODE
        ]);
        List<Document__c> documents = [
            SELECT Id, Lead__c, Account__c, Opportunity__c FROM Document__c WHERE Lead__c IN :leadIds WITH SYSTEM_MODE
        ];
        for (Document__c document : documents) {
            Lead record = leads.get(document.Lead__c);
            if (document.Account__c == null) {
                document.Account__c = record.ConvertedAccountId;
            }
            if (document.Opportunity__c == null) {
                document.Opportunity__c = record.ConvertedOpportunityId;
            }
        }
        for (Database.SaveResult result : Database.update(documents, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Lead document not moved to the customer: ' + result.getErrors());
            }
        }
    }

    // The Hand Over Lead Status; null when blank (no hand-over)
    private static String handOverStage() {
        return setting == null || String.isBlank(setting.Hand_Over_Lead_Status__c) ? null : setting.Hand_Over_Lead_Status__c.trim();
    }
}