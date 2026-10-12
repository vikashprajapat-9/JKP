@isTest
private class partnerUserProfileControllerTest {

    @isTest
    static void showsThePartnersOwnDetailsAndAccount() {
        User partner = PartnerPortalTestUser.create();
        Id partnerAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :partner.Id].Contact.AccountId;
        update new Account(Id = partnerAccountId, Partner_Type__c = 'Temporary', Temporary_Access_End_Date__c = Date.newInstance(2026, 11, 2));
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = partner.Id, FirstName = 'Kamal', LastName = 'Perera', Phone = '0771234567', MobilePhone = '0719876543');
        }

        partnerUserProfileController.UserProfileWrapper profile;
        System.runAs(partner) {
            profile = partnerUserProfileController.getUserProfile();
        }

        System.assertEquals('Kamal Perera', profile.name);
        System.assertEquals('KP', profile.initials, 'As the top bar shows them');
        System.assertEquals(partner.Email, profile.email);
        System.assertEquals('0719876543', profile.mobile, 'The mobile number first');
        System.assertEquals('Portal Test Partner', profile.companyName);
        System.assertEquals('Temporary', profile.partnerType, 'The Partner Type label');
        System.assertEquals('02-11-2026', profile.expiryDate);
    }

    @isTest
    static void leavesOutWhatThePartnerAccountDoesNotHave() {
        User partner = PartnerPortalTestUser.create();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = partner.Id, Phone = '0771234567', MobilePhone = null);
        }

        partnerUserProfileController.UserProfileWrapper profile;
        System.runAs(partner) {
            profile = partnerUserProfileController.getUserProfile();
        }

        System.assertEquals('0771234567', profile.mobile, 'The phone when there is no mobile number');
        System.assertEquals(null, profile.partnerType, 'No made-up Partner Type');
        System.assertEquals('-', profile.expiryDate);
    }

    @isTest
    static void aUserWithoutAPartnerAccountHasNoCompany() {
        partnerUserProfileController.UserProfileWrapper profile = partnerUserProfileController.getUserProfile();

        System.assertEquals(UserInfo.getName(), profile.name);
        System.assertEquals(null, profile.companyName);
        System.assertEquals(null, profile.partnerType);
        System.assertEquals('-', profile.expiryDate);
    }

    // Once the signed agent contract is on record its end date is the expiry; an executive shows their channel head's
    // partner type and expiry
    @isTest
    static void showsTheSignedContractsEndDateAndTheHeadsForAnExecutive() {
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>());
        Id executiveAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :executive.Id].Contact.AccountId;
        Id headId = [SELECT Channel_Head__c FROM Account WHERE Id = :executiveAccountId].Channel_Head__c;
        update new List<Account>{
            new Account(Id = headId, Partner_Type__c = 'Exclusive', Temporary_Access_End_Date__c = Date.newInstance(2026, 11, 2)),
            new Account(Id = executiveAccountId, Partner_Type__c = 'Temporary', Temporary_Access_End_Date__c = Date.newInstance(2026, 10, 1))
        };
        insert new Contract(AccountId = headId, Status = 'Draft', Contract_Stage__c = 'Completed',
            Contract_Start__c = Date.newInstance(2026, 11, 1), Contract_End__c = Date.newInstance(2027, 10, 31));

        partnerUserProfileController.UserProfileWrapper profile;
        System.runAs(executive) {
            profile = partnerUserProfileController.getUserProfile();
        }

        System.assertEquals('Exclusive', profile.partnerType, 'The channel head\'s');
        System.assertEquals('31-10-2027', profile.expiryDate, 'The signed contract\'s end date');
    }
}