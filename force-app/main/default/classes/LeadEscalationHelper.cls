public class LeadEscalationHelper {

    // temporarily hardcoded
    private static final String MARKETING_EMAIL = 'mahima.util@gmail.com';
    private static final Id TEST_USER_ID = '005f6000004dGI1AAM';

    private static Lead_Assignment_History__c getCurrentAssignmentHistory(Id leadId) {
        List<Lead_Assignment_History__c> histories = [SELECT Id,Lead__c,Lead_Assigned_To__c,OwnerId,SLA1__c,CreatedDate FROM Lead_Assignment_History__c
                                                        WHERE Lead__c = :leadId ORDER BY CreatedDate DESC   ];

        if (histories.isEmpty()) {
            return null;
        }
        return histories[0];
    }

    public static void sendHotLeadEscalation(Id leadId) {
        Lead_Assignment_History__c history = getCurrentAssignmentHistory(leadId);
        if (history == null) {
            System.debug('No Lead Assignment History found for Lead: ' + leadId );
            return;
        }
        if (history.SLA1__c == true) {
            System.debug( 'SLA1 already TRUE for Hot Lead: ' + leadId);
            return;
        }

        sendEmail(leadId, 'HotLeadEscalationEmail');
        sendNotification(leadId, 'Hot_Lead_Escalation',
            'Hot Lead Escalation',
            'A Hot Lead has not been contacted within 1 hour of assignment.');
        
        history.SLA1__c = true;
        update history;
        
        Group reDistributionQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Re_Distributin_Queue' LIMIT 1 ];
        Lead leadToUpdate = new Lead(Id = leadId,OwnerId = reDistributionQueue.Id ,Is_Re_Distributin_Queue_Assigned__c  = true);
        update leadToUpdate;
        System.debug( 'SLA1 marked TRUE and Lead moved to	Re_Distributin_Queue : ' + leadId );
    }

    public static void sendWarmLeadEscalation(Id leadId) {
        Lead_Assignment_History__c history = getCurrentAssignmentHistory(leadId);
        if (history == null) {
            System.debug('No Lead Assignment History found for Lead: ' + leadId );
            return;
        }
        if (history.SLA1__c == true) {
            System.debug( 'SLA1 already TRUE for warm lead: ' + leadId);
            return;
        }
        sendEmail(leadId, 'WarmLeadEscalation');
        sendNotification(leadId, 'Warm_Lead_Escalation',
            'Warm Lead Escalation',
            'A Warm Lead has not been contacted within 4 hours of assignment.');
            
        history.SLA1__c = true;
        update history;
        Group reDistributionQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Re_Distributin_Queue' LIMIT 1 ];
        Lead leadToUpdate = new Lead(Id = leadId,OwnerId = reDistributionQueue.Id, Is_Re_Distributin_Queue_Assigned__c  = true );

        update leadToUpdate;
        System.debug( 'SLA1 marked TRUE and Lead moved to	Re_Distributin_Queue : ' + leadId );
    }

    private static void sendEmail(Id leadId, String templateDeveloperName) {
            Lead ld = [  SELECT Id, Name,Owner.Name, Project__r.Name,Normalised_Phone__c,Phone,Status,Lead_Classification__c,
                        Lead_Assigned_Date_Time__c FROM Lead WHERE Id = :leadId];
            EmailTemplate template = [ SELECT Id, Subject,HtmlValue FROM EmailTemplate WHERE DeveloperName = :templateDeveloperName LIMIT 1  ];
            OrgWideEmailAddress owea = [SELECT Id FROM OrgWideEmailAddress  LIMIT 1  ];
            String htmlBody = template.HtmlValue;

            htmlBody = htmlBody.replace('{!Lead.Name}', ld.Name != null ? ld.Name : '');
            htmlBody = htmlBody.replace('{!Lead.Phone}', ld.Normalised_Phone__c != null ? ld.Normalised_Phone__c : '');
            htmlBody = htmlBody.replace('{!Lead.Status}', ld.Status != null ? ld.Status : '');
            htmlBody = htmlBody.replace('{!Lead.Classification__c}',
                                        ld.Lead_Classification__c != null ? ld.Lead_Classification__c : '');
            htmlBody = htmlBody.replace('{!Lead.Lead_Assigned_Date_Time__c}',
                                        ld.Lead_Assigned_Date_Time__c != null ?
                                        String.valueOf(ld.Lead_Assigned_Date_Time__c) : '');
            htmlBody = htmlBody.replace('{!Lead.OwnerFullName}',
                                        ld.Owner != null ? ld.Owner.Name : '');
            htmlBody = htmlBody.replace('{!Lead.Project__r}',
                                        ld.Project__r != null ? ld.Project__r.Name : '');

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

            mail.setToAddresses(new String[]{MARKETING_EMAIL});
            mail.setSubject(template.Subject);
            mail.setHtmlBody(htmlBody);
            mail.setOrgWideEmailAddressId(owea.Id);
            mail.setSaveAsActivity(false);

            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
        }

    private static void sendNotification(  Id leadId,String notificationDeveloperName,String title, String body ) {
        CustomNotificationType typeRec = [SELECT Id  FROM CustomNotificationType  WHERE DeveloperName = :notificationDeveloperName LIMIT 1 ];

        Messaging.CustomNotification notification = new Messaging.CustomNotification();

        notification.setNotificationTypeId(typeRec.Id);
        notification.setTitle(title);
        notification.setBody(body);
        notification.setTargetId(leadId);

        notification.send(new Set<String>{ TEST_USER_ID });
    }
    public static void sendSLA2Notification(Id leadId) {
        CustomNotificationType typeRec = [ SELECT Id  FROM CustomNotificationType WHERE DeveloperName = 'Lead_Follow_Up_SLA2' LIMIT 1  ];
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(typeRec.Id);
        notification.setTitle('Lead Follow-Up SLA Breached' );
        notification.setBody('A mandatory Lead follow-up was not completed on the scheduled day.'  );
        notification.setTargetId(leadId);
        notification.send( new Set<String>{TEST_USER_ID } );
    }
}