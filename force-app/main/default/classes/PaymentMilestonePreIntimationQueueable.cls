public class PaymentMilestonePreIntimationQueueable implements Queueable {
    public void execute(QueueableContext context) {
        Date today = Date.today();
        Date fifteenDaysFromToday = today.addDays(15);
        List<Payment_Schedule__c> schedules = [
            SELECT Id,
                Name,
                Installment__c,
                Due_Date__c,
                Payment_Scheme_Installment__r.Milestone_Completion_Date__c,
                Total_Due_Amount__c,
                Total_Amount_Inclusive_Of_Tax__c,
                Demand_Letter_Sent__c,
                Intimation_Sent__c,
                Opportunity__c,
                Opportunity__r.Name,
                Opportunity__r.AccountId,
                Opportunity__r.Account.Name,
                Opportunity__r.Unit__c,
                Opportunity__r.Unit__r.Name,
                Opportunity__r.Unit__r.Floor__r.Name,
                Opportunity__r.Unit__r.Floor__r.Block__r.Name,
                Opportunity__r.Project__c,
                Opportunity__r.Project__r.Name
            FROM Payment_Schedule__c
            WHERE Payment_Scheme_Installment__r.Milestone_Completion_Date__c > :fifteenDaysFromToday
            AND Intimation_Sent__c = false
            ORDER BY Due_Date__c ASC
        ];

        if (schedules.isEmpty()) {
            System.debug('No Payment Schedule found for Payment Milestone Pre-Intimation.');
            return;
        }

        List<EmailTemplate> templates = [
            SELECT Id, DeveloperName, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = 'Email_for_Payment_Milestone_Pre_Intimation'
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            System.debug('Email template not found: Email_for_Payment_Milestone_Pre_Intimation');
            return;
        }

        EmailTemplate template = templates[0];

        List<OrgWideEmailAddress> oweaList = [
            SELECT Id
            FROM OrgWideEmailAddress
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Map<String, ContentAsset> logoAssetsMap = new Map<String, ContentAsset>();
        for (ContentAsset asset : [
            SELECT Id, DeveloperName, MasterLabel, ContentDocumentId,IsVisibleByExternalUsers
            FROM ContentAsset
            WHERE DeveloperName IN ('Logo_White', 'Logo_Blue')
            WITH SYSTEM_MODE
        ]) {
            logoAssetsMap.put(asset.DeveloperName, asset);
        }

        String orgId = UserInfo.getOrganizationId();
        String orgDomainUrl = URL.getOrgDomainUrl().toExternalForm();
        String jkpWhiteLogoUrl = '';
        String jkpBlueLogoUrl = '';
        if (logoAssetsMap.containsKey('Logo_White')) {
            ContentAsset whiteLogo = logoAssetsMap.get('Logo_White');
            jkpWhiteLogoUrl = orgDomainUrl + '/file-asset-public/' + whiteLogo.DeveloperName +'?oid=' + orgId;
        }

        if (logoAssetsMap.containsKey('Logo_Blue')) {
            ContentAsset blueLogo = logoAssetsMap.get('Logo_Blue');
            jkpBlueLogoUrl = orgDomainUrl + '/file-asset-public/' + blueLogo.DeveloperName + '?oid=' + orgId;
        }

        Set<Id> accountIds = new Set<Id>();
        for (Payment_Schedule__c schedule : schedules) {
            if (schedule.Opportunity__r != null &&
                schedule.Opportunity__r.AccountId != null) {
                accountIds.add(schedule.Opportunity__r.AccountId);
            }
        }
        if (accountIds.isEmpty()) {
            System.debug('No Account found for Payment Schedules.');
            return;
        }

        Map<Id, Account> accountMap = new Map<Id, Account>([SELECT Id, Name, Email__c FROM Account  WHERE Id IN :accountIds WITH SYSTEM_MODE ]);
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c schedule : schedules) {
            if (schedule.Opportunity__r == null ||
                schedule.Opportunity__r.AccountId == null) {
                continue;
            }
            Id accountId = schedule.Opportunity__r.AccountId;
            if (!accountMap.containsKey(accountId)) {
                continue;
            }
            Account account = accountMap.get(accountId);
            if (String.isBlank(account.Email__c)) {
                System.debug('No email found for Account: ' + account.Name );
                continue;
            }
            String body = template.HtmlValue;
            String projectName = '';
            if (schedule.Opportunity__r.Project__r != null) {
                projectName = schedule.Opportunity__r.Project__r.Name;
            }
            String unitName = '';
            if (schedule.Opportunity__r.Unit__r != null) {
                unitName = schedule.Opportunity__r.Unit__r.Name;
            }
            String milestoneName = '';
            if (schedule.Installment__c != null) {
                milestoneName = String.valueOf(schedule.Installment__c);
            }

            body = body.replace('{!Contact.Name}', account.Name == null ? '' : account.Name );
            body = body.replace('{!Project.Name}', projectName);
            body = body.replace('{!Unit.Name}', unitName);
            body = body.replace('{!Milestone_Name}', milestoneName);
            body = body.replace('{!Company__c.Name}','John Keells Properties'); 
            body = body.replace('{{JKP_LOGO_WHITE}}',jkpWhiteLogoUrl );
            body = body.replace('{{JKP_LOGO_BLUE}}',jkpBlueLogoUrl);

            String subject = template.Subject;
            subject = subject.replace('{!Project.Name}',projectName);
            subject = subject.replace('{!Unit.Name}',unitName);
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses( new String[] { account.Email__c } );
            if (!oweaList.isEmpty()) {
                mail.setOrgWideEmailAddressId(oweaList[0].Id);
            }
            mail.setSaveAsActivity(false);
            mail.setHtmlBody(body);
            mail.setSubject(subject);
            emailsToSend.add(mail);
            schedulesToUpdate.add(new Payment_Schedule__c(Id = schedule.Id,Intimation_Sent__c = true));
        }

        if (!emailsToSend.isEmpty()) {
            Messaging.sendEmail(emailsToSend);
            System.debug('Payment Milestone Pre-Intimation emails sent: ' + emailsToSend.size());

            if (!schedulesToUpdate.isEmpty()) {
                update schedulesToUpdate;
                System.debug('Payment Schedules marked as Intimation Sent: ' +schedulesToUpdate.size());
            }
        }
    }
}