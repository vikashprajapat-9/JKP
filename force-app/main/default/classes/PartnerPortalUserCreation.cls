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

        // 1. Fetch Accounts and their EXISTING Contacts
        List<Account> accounts = [
            SELECT Id, Name, Email__c, Phone,
                   (SELECT Id, FirstName, LastName, Email, Phone FROM Contacts ORDER BY CreatedDate ASC LIMIT 1) 
           		    FROM Account 
            WHERE Id IN :accountIds
        ];

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

        // 3. Update Account: Enable as Partner & Set 30-Day Access.
        for (Account acc : accounts) {
            acc.IsPartner                      = true;
            acc.Partner_Type__c                = 'Temporary';
            acc.Temporary_Access_Start_Date__c = Date.today();
            acc.Temporary_Access_End_Date__c   = Date.today().addDays(30);
            Integer countDays=acc.Temporary_Access_Start_Date__c.daysBetween(acc.Temporary_Access_End_Date__c);
             System.debug('Portal Remaining Days==>'+countDays);
        }
        update accounts;
        System.debug('>>> [PartnerPortal] Accounts updated to Partner with 30-day access.');

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
            String fName = String.isNotBlank(c.FirstName) ? c.FirstName : '';
            String lName = String.isNotBlank(c.LastName) ? c.LastName : acc.Name;
            String userEmail = String.isNotBlank(c.Email) ? c.Email : acc.Email__c;

            String nick = fName.length() >= 4 ? fName.substring(0, 4) : 'part';
            String randomDigits = String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 4);

            User u = new User();
            u.ContactId         = c.Id; // Links to your existing Contact!
            u.ProfileId         = partnerProfileId;
            u.FirstName         = fName;
            u.LastName          = lName;
            u.Email             = userEmail;
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
            insert usersToInsert;
            System.debug('>>> [PartnerPortal] Successfully created Partner Users: ' + usersToInsert);
        }
    }
}