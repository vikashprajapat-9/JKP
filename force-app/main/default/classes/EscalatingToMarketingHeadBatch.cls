public  class EscalatingToMarketingHeadBatch implements Database.Batchable<sObject> {
    public Database.QueryLocator start(Database.BatchableContext bc){
        Datetime thirtyMinutesAgo = Datetime.now().addMinutes(-30);
        return Database.getQueryLocator([
            SELECT Id, Name, CreatedDate
            FROM Lead
            WHERE Lead_Classification__c = 'Hot'
            AND CreatedDate < :thirtyMinutesAgo
            AND Is_User_Assigned__c = false
            AND Pre_Sales_Team_Member__c = null
            AND Owner.Name = 'Lead Assignment Queue'
            AND Unassigned_for_Threshold__c = false
        ]);
    }
    public void execute(Database.BatchableContext bc,List<Lead> leadsList){
        if(leadsList.isEmpty()){
            return;
        }
        List<User> seniorSalesManager = [
            SELECT Id, Email, Name
            FROM User
            // WHERE UserRole.Name = 'Senior Manager Sales'
            WHERE Name like '%Isha%'
            AND IsActive = true
            LIMIT 1
        ];
        List<EmailTemplate> template = [
            SELECT Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = 'Hot_Lead_Escalation_To_Marketing_Head'
            LIMIT 1
        ];
        String baseUrl = URL.getOrgDomainUrl().toExternalForm(); 
       String table =
        '<table style="width:100%;border-collapse:collapse;">' +
        '<tr style="background:#1A2149;color:white;">' +
        '<th style="padding:10px;border:1px solid #ddd;">Lead Name</th>' +
        '<th style="padding:10px;border:1px solid #ddd;">Created Date</th>' +
        '</tr>';

        for(Lead ld : leadsList){
            ld.Unassigned_for_Threshold__c = true;

            table +=
            '<tr>' +
            '<td style="padding:10px;border:1px solid #ddd;">' +
            '<a href="' + baseUrl + '/' + ld.Id + '">' +
            ld.Name +
            '</a>' +
            '</td>' +

            '<td style="padding:10px;border:1px solid #ddd;">' +
            ld.CreatedDate.format('dd-MMM-yyyy hh:mm a') +
            '</td>' +

            '</tr>';
        }

        table += '</table>';

        String body = template[0].HtmlValue.replace('{{LeadTable}}', table);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

        email.setToAddresses(new List<String>{seniorSalesManager[0].Email});
        email.setSubject(template[0].Subject);
        email.setHtmlBody(body);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{email});

        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        List<CustomNotificationType> notificationType = [
            SELECT Id 
            FROM CustomNotificationType 
            WHERE DeveloperName = 'Hot_Leads_Pending_Assignment' 
            LIMIT 1
        ];
        notification.setTitle('Hot Leads Pending Assignment');
        notification.setBody('Please review and assign the pending Hot Leads.');
        notification.setNotificationTypeId(notificationType[0].Id);

        notification.setTargetPageRef(
            '{"type": "standard__objectPage","attributes": {"objectApiName": "Lead","actionName": "list"},"state":{"filterName":"Lead_Assignment_Queue_Lead"}}'
        );
        notification.send(new Set<String>{ String.valueOf(seniorSalesManager[0].Id) });

        update leadsList;
    }

    public void finish(Database.BatchableContext bc){

    }
}