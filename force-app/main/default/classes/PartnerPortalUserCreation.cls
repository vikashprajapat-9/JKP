public without sharing class PartnerPortalUserCreation {

    @InvocableMethod(label='Enable Partner Portal User' description='Enables Account as Partner, sets 30-day access, and creates Partner User')
    public static void enablePartnerUser(List<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) 
            return;

        // passed accountIds
        createPartnerUsersAsync(accountIds);
    }

	//creation of partner portal user
    @future
    public static void createPartnerUsersAsync(List<Id> accountIds) {

        // 1. Fetch Accounts and their EXISTING Contacts. A partner that is Access Denied or Terminated, and an executive
        // of one, get no access, login or email: an approval that comes after the access ended must not open a login
        // again (it would use a licence until the nightly job switched it off).
        List<Account> accounts = new List<Account>();
        for (Account acc : [
            SELECT Id, Name, Email__c, Phone, Partner_Type__c, Channel_Head__c, Channel_Head__r.Partner_Type__c,
                   (SELECT Id, FirstName, LastName, Email, Phone FROM Contacts ORDER BY CreatedDate ASC LIMIT 1)
            FROM Account
            WHERE Id IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            if (PartnerTemporaryAccess.isClosed(acc.Partner_Type__c)
                    || (acc.Channel_Head__c != null && PartnerTemporaryAccess.isClosed(acc.Channel_Head__r.Partner_Type__c))) {
                System.debug(LoggingLevel.ERROR, '>>> [PartnerPortal] No login for ' + acc.Name + ': the partner or its channel head is Access Denied or Terminated');
                continue;
            }
            accounts.add(acc);
        }
        if (accounts.isEmpty()) {
            return;
        }

        // 2. Fetch Partner Community Profile.
        List<Profile> profiles = [
            SELECT Id, Name 
            FROM Profile 
            WHERE Name IN ('Partner Community')
            ORDER BY Name ASC
            LIMIT 1
        ];

        if (profiles.isEmpty()) {
            System.debug('>>> [PartnerPortal] Error: Partner Community Profile not found!');
            return;
        }
        Id partnerProfileId = profiles[0].Id;

        // 3. Update Account: Enable as Partner & Set 30-Day Access. An executive has no access of its own: it works under
        // its channel head's (PartnerTemporaryAccess), so its Partner Type and temporary access dates stay blank.
        for (Account acc : accounts) {
            acc.IsPartner                      = true;
            if (acc.Channel_Head__c != null) {
                acc.Partner_Type__c                = null;
                acc.Temporary_Access_Start_Date__c = null;
                acc.Temporary_Access_End_Date__c   = null;
                continue;
            }
            acc.Partner_Type__c                = 'Temporary';
            acc.Temporary_Access_Start_Date__c = Date.today();
            acc.Temporary_Access_End_Date__c   = Date.today().addDays(30);
            Integer countDays=acc.Temporary_Access_Start_Date__c.daysBetween(acc.Temporary_Access_End_Date__c);
             System.debug('Portal Remaining Days==>'+countDays);
        }
        update accounts;
        System.debug('>>> [PartnerPortal] Accounts updated to Partner: 30-day access for channel heads, none of their own for executives.');

        // 4. Create Partner Community User using the EXISTING Contact
        List<User> usersToInsert = new List<User>();

        for (Account acc : accounts) {
            if (acc.Contacts == null || acc.Contacts.isEmpty()) {
                System.debug('>>> [PartnerPortal] Warning: No Contact found for Account: ' + acc.Name);
                continue;
            }

            Contact c = acc.Contacts[0]; // Existing Contact

            // Check if User already exists for this Contact to avoid duplicates
            List<User> existingUsers = [SELECT Id FROM User WHERE ContactId = :c.Id LIMIT 1];
            if (!existingUsers.isEmpty()) {
                System.debug('>>> [PartnerPortal] User already exists for Contact: ' + c.Id);
                continue;
            }

            // Fallback for names if not populated on Contact
            String xphone= String.isNotBlank    (c.Phone)     ? c.Phone:acc.Phone;
            String fName = String.isNotBlank    (c.FirstName) ? c.FirstName : '';
            String lName = String.isNotBlank    (c.LastName)  ? c.LastName : acc.Name;
            String userEmail = String.isNotBlank(c.Email)     ? c.Email : acc.Email__c;

            String nick = fName.length() >= 4 ? fName.substring(0, 4) : 'part';
            String randomDigits = String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 4);

            User u = new User();
            u.ContactId         = c.Id; // Links to your existing Contact!
            u.ProfileId         = partnerProfileId;
            u.FirstName         = fName;
            u.LastName          = lName;
            u.Email             = userEmail;
            u.Phone				= xphone;
            u.Username          = userEmail + '.partner'; // Must be unique globally
            u.Alias             = (lName.length() > 5 ? lName.substring(0, 5) : lName);
            u.CommunityNickname = nick + randomDigits;
            u.TimeZoneSidKey    = 'Asia/Kolkata'; // Or your org's timezone
            u.LocaleSidKey      = 'en_US';
            u.EmailEncodingKey  = 'UTF-8';
            u.LanguageLocaleKey = 'en_US';
            u.IsActive          = true;

            usersToInsert.add(u);
        }

        if (!usersToInsert.isEmpty()) {
            // Email each new partner the Partner Portal welcome email (their username and a link to set the password)
            Database.DMLOptions options = new Database.DMLOptions();
            options.EmailHeader.triggerUserEmail = true;
            Database.insert(usersToInsert, options);
            System.debug('>>> [PartnerPortal] Successfully created Partner Users: ' + usersToInsert);
            sendAccessEmails(usersToInsert);
        }
    }

    // How many access emails the last run sent, and how many of them to executives (for tests)
    @TestVisible
    private static Integer accessEmailsSent = 0;
    @TestVisible
    private static Integer executiveAccessEmailsSent = 0;

    // Tests replace the org's Partner Registration Setting with a record of their own
    @TestVisible
    private static Partner_Registration_Setting__mdt setting {
        get {
            if (setting == null) {
                setting = Partner_Registration_Setting__mdt.getInstance('Default');
            }
            return setting;
        }
        set;
    }

    // Tells each new partner's contact that the Partner Portal access is approved, from the partner email sender: a
    // channel head about the temporary access and its dates (Access Email Template of the Partner Registration Setting),
    // an executive about working under its channel head (Executive Access Email Template; an executive has no dates).
    // No email where the setting names no template. A failed email does not undo the access.
    private static void sendAccessEmails(List<User> partners) {
        if (setting == null) {
            return;
        }
        Id headTemplateId = templateId(setting.Access_Email_Template__c);
        Id executiveTemplateId = templateId(setting.Executive_Access_Email_Template__c);
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Boolean> toExecutive = new List<Boolean>();
        for (Contact partnerContact : [
            SELECT Id, AccountId, Account.Channel_Head__c FROM Contact WHERE Id IN (SELECT ContactId FROM User WHERE Id IN :partners)
            WITH SYSTEM_MODE
        ]) {
            Boolean isExecutive = partnerContact.Account.Channel_Head__c != null;
            Id chosenTemplateId = isExecutive ? executiveTemplateId : headTemplateId;
            if (chosenTemplateId == null) {
                continue;
            }
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTemplateId(chosenTemplateId);
            email.setTargetObjectId(partnerContact.Id);
            email.setWhatId(partnerContact.AccountId);
            email.setSaveAsActivity(false);
            emails.add(email);
            toExecutive.add(isExecutive);
        }
        if (emails.isEmpty()) {
            return;
        }
        List<Messaging.SendEmailResult> results = PartnerEmailSender.send(emails);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                accessEmailsSent++;
                if (toExecutive[i]) {
                    executiveAccessEmailsSent++;
                }
            } else {
                System.debug(LoggingLevel.ERROR, '>>> [PartnerPortal] Access email not sent: ' + results[i].getErrors());
            }
        }
    }

    // The email template with this developer name; null when the name is blank or no such template exists
    private static Id templateId(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        List<EmailTemplate> templates = [
            SELECT Id FROM EmailTemplate WHERE DeveloperName = :developerName.trim() WITH SYSTEM_MODE LIMIT 1
        ];
        if (templates.isEmpty()) {
            System.debug(LoggingLevel.ERROR, '>>> [PartnerPortal] Access email template not found: ' + developerName);
            return null;
        }
        return templates[0].Id;
    }
}