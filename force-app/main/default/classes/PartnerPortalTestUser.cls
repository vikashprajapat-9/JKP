// A Partner Community user for tests. Like real partners, it has no record access to projects, their files or Portal
// Info, so portal Apex must be tested as this user.
@isTest
public class PartnerPortalTestUser {

    public static User create() {
        return create(partnerPortalRegistrationController.partnerRecordTypeId());
    }

    // A partner whose account has the given record type (real partners have the channel partner one)
    public static User create(Id accountRecordTypeId) {
        UserRole role = new UserRole(Name = 'Portal Test Owner');
        User owner = newUser('System Administrator', 'powner');
        User partner = newUser('Partner Community', 'ppartner');
        // Roles and users in their own context, so the test can still insert records
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert role;
            owner.UserRoleId = role.Id;
            insert owner;
        }
        // A partner's account must belong to a user with a role, and be a channel partner to log in to the portal
        System.runAs(owner) {
            Account account = new Account(Name = 'Portal Test Partner', RecordTypeId = accountRecordTypeId);
            insert account;
            Contact contact = new Contact(LastName = 'Partner', AccountId = account.Id);
            insert contact;
            partner.ContactId = contact.Id;
            insert partner;
        }
        return partner;
    }

    // An executive: a partner whose channel partner account has a Channel Head (an account without a portal user) and
    // Project Access to the given projects only
    public static User createExecutive(List<Id> projectIds) {
        User executive = create();
        Id executiveAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :executive.Id].Contact.AccountId;
        Account head = new Account(Name = 'Portal Test Channel Head', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId());
        insert head;
        update new Account(Id = executiveAccountId, Channel_Head__c = head.Id);
        List<Project_Access__c> projectAccess = new List<Project_Access__c>();
        for (Id projectId : projectIds) {
            projectAccess.add(new Project_Access__c(Account__c = executiveAccountId, Project__c = projectId));
        }
        insert projectAccess;
        return executive;
    }

    private static Integer executives = 0;

    // An executive with a portal user of its own under this channel head. The head must come from create(): its owner
    // has a role, which the owner of a portal account needs. create() can run once per test (fixed usernames); this can
    // run several times.
    public static User createExecutiveOf(Id headAccountId) {
        Id ownerId = [SELECT OwnerId FROM Account WHERE Id = :headAccountId].OwnerId;
        Integer n = ++executives;
        User executive = newUser('Partner Community', 'pexec' + n);
        System.runAs(new User(Id = ownerId)) {
            Account account = new Account(Name = 'Portal Test Executive ' + n, RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
                Channel_Head__c = headAccountId, Document_Id__c = 'test-folder-executive-' + n);
            insert account;
            Contact contact = new Contact(LastName = 'Executive ' + n, AccountId = account.Id);
            insert contact;
            executive.ContactId = contact.Id;
            insert executive;
        }
        return executive;
    }

    private static User newUser(String profileName, String alias) {
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1].Id,
            LastName = 'Portal Test ' + alias,
            Alias = alias,
            Email = alias + '@portal-test.example.com',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@portal-test.example.com',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}