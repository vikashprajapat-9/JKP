@isTest
private class CustomerPortalProfileControllerTest {

    private static final String CUSTOMER_ALIAS = 'cpfcust';
    private static final String PARTNER_ALIAS = 'cpfpart';
    private static final String CUSTOMER_EMAIL = 'jane.customer@customer-profile-test.example.com';
    private static final String CURRENT_PASSWORD = 'Current#Pass1';
    private static final String NEW_PASSWORD = 'NewPass#2026';
    // A 1x1 PNG and the starts of a JPEG, a PDF and a GIF (Salesforce keeps the bytes as they are)
    private static final String PNG_HEX = '89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C489'
        + '0000000D49444154789C626001000000FFFF03000006000557BFABD40000000049454E44AE426082';
    private static final String JPEG_HEX = 'FFD8FFE000104A46494600010100000100010000FFD9';
    private static final String PDF_HEX = '255044462D312E340A25E2E3CFD30A';
    private static final String GIF_HEX = '474946383961010001008000000000000000002C00000000010001000002024401003B';

    // Stands in for Site.changePassword: records what it was given (new password, confirmation, current password) and
    // answers as the test says
    private class FakeSite extends CustomerPortalController.SitePasswordChange {
        public PageReference answer = new PageReference('/SFA/s/');
        public Boolean fails = false;
        public List<String> calls = new List<String>();

        public override PageReference changePassword(String newPassword, String verifyNewPassword, String oldPassword) {
            calls.add(newPassword + '|' + verifyNewPassword + '|' + oldPassword);
            if (fails) {
                throw new FakeSiteException('Your old password is invalid: ' + oldPassword);
            }
            return answer;
        }
    }

    private class FakeSiteException extends Exception {}

    private static FakeSite fakeSite() {
        FakeSite fake = new FakeSite();
        CustomerPortalController.sitePasswords = fake;
        return fake;
    }

    // A customer login (Jane, on a Customer account) and a login on a Channel Partner account, both with the customer
    // profile, on accounts whose owner has a role (a portal account needs one)
    // Salesforce stamps ContentVersion.NetworkId for a community user and refuses the save outside a site session
    // (INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY: [NetworkId]). An Apex test has no site, so the file itself cannot
    // be saved here, while everything before the save (access, type, size, name, versions) still runs. Saving a picture
    // and seeing it on the account was checked on the live site on 2026-10-19 with a throwaway customer. These tests
    // therefore check the saved file only where the platform allowed the save.
    private static Boolean pictureSavedHere = true;

    private static CustomerPortalController.Profile tryUpload(String data, String fileName, String contentType) {
        try {
            return CustomerPortalController.uploadProfilePicture(data, fileName, contentType);
        } catch (AuraHandledException e) {
            if (CustomerPortalController.PICTURE_NOT_SAVED.equals(e.getMessage())) {
                pictureSavedHere = false;
                return null;
            }
            throw e;
        }
    }

    @testSetup
    static void createLogins() {
        UserRole role = new UserRole(Name = 'Customer Profile Test Owner');
        User owner = newUser([SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id, 'cpfown', 'Owner',
            'owner@customer-profile-test.example.com');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert role;
            owner.UserRoleId = role.Id;
            insert owner;
        }
        Id customerProfileId = [SELECT Id FROM Profile WHERE Name = 'Customer Community Plus User Cloned' LIMIT 1].Id;
        System.runAs(owner) {
            Account customerAccount = new Account(Name = 'Profile Test Customer', RecordTypeId = recordTypeId('Customer'));
            Account partnerAccount = new Account(Name = 'Profile Test Partner', RecordTypeId = recordTypeId('Channel_Partner'));
            insert new List<Account>{ customerAccount, partnerAccount };
            Contact jane = new Contact(
                FirstName = 'Jane',
                LastName = 'Customer',
                Email = CUSTOMER_EMAIL,
                MobilePhone = '+94 771234567',
                Department = 'Sales',
                AccountId = customerAccount.Id
            );
            Contact pat = new Contact(FirstName = 'Pat', LastName = 'Partner', Email = 'pat.partner@customer-profile-test.example.com',
                AccountId = partnerAccount.Id);
            insert new List<Contact>{ jane, pat };
            User customer = newUser(customerProfileId, CUSTOMER_ALIAS, 'Customer', CUSTOMER_EMAIL);
            customer.FirstName = 'Jane';
            customer.MobilePhone = '+94 771234567';
            customer.ContactId = jane.Id;
            User partner = newUser(customerProfileId, PARTNER_ALIAS, 'Partner', pat.Email);
            partner.FirstName = 'Pat';
            partner.ContactId = pat.Id;
            insert new List<User>{ customer, partner };
        }
    }

    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    private static String usernameOf(String alias) {
        return alias + '.' + UserInfo.getOrganizationId() + '@customer-profile-test.example.com';
    }

    private static User newUser(Id profileId, String alias, String lastName, String email) {
        return new User(
            ProfileId = profileId,
            LastName = lastName,
            Alias = alias,
            Email = email,
            Username = usernameOf(alias),
            TimeZoneSidKey = 'Asia/Colombo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static User customer() {
        return [SELECT Id, Name, Username, ContactId, Contact.AccountId FROM User WHERE Username = :usernameOf(CUSTOMER_ALIAS) LIMIT 1];
    }

    private static User partner() {
        return [SELECT Id FROM User WHERE Username = :usernameOf(PARTNER_ALIAS) LIMIT 1];
    }

    private static User siteGuest() {
        return [SELECT Id FROM User WHERE UserType = 'Guest' AND Profile.Name = 'SFA Profile' AND IsActive = true LIMIT 1];
    }

    private static String base64(String hex) {
        return EncodingUtil.base64Encode(EncodingUtil.convertFromHex(hex));
    }

    // Base64 of a PNG of exactly this many bytes
    private static String pngOfSize(Integer bytes) {
        return base64('89504E470D0A1A0A' + '00'.repeat(bytes - 8));
    }

    // The ContentDocument Id the account's Profile Picture Document Id holds
    private static Id pictureIdOf(Id accountId) {
        String value = [SELECT Profile_Picture_Document_Id__c FROM Account WHERE Id = :accountId].Profile_Picture_Document_Id__c;
        return value == null ? null : Id.valueOf(value);
    }

    private static Id documentOf(ContentVersion version) {
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    // The message the page shows, or null when the call went through
    private static String updateError(String firstName, String lastName, String email, String code, String phone, String department) {
        try {
            CustomerPortalController.updateProfile(firstName, lastName, email, code, phone, department);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    // The message the upload refused with, or null when it went through. The platform's own refusal outside a site
    // (see pictureSavedHere) counts as "went through": the picture itself passed every check of this class.
    private static String uploadError(String data, String fileName, String contentType) {
        try {
            CustomerPortalController.uploadProfilePicture(data, fileName, contentType);
            return null;
        } catch (AuraHandledException e) {
            if (CustomerPortalController.PICTURE_NOT_SAVED.equals(e.getMessage())) {
                pictureSavedHere = false;
                return null;
            }
            return e.getMessage();
        }
    }

    private static String passwordError(String oldPassword, String newPassword, String confirmPassword) {
        try {
            CustomerPortalController.changePassword(oldPassword, newPassword, confirmPassword);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    // The message each of the page's calls gets
    private static Map<String, String> errorsOfEveryCall() {
        Map<String, String> errors = new Map<String, String>();
        try {
            CustomerPortalController.getProfile();
            errors.put('getProfile', null);
        } catch (AuraHandledException e) {
            errors.put('getProfile', e.getMessage());
        }
        errors.put('updateProfile', updateError('Jane', 'Customer', CUSTOMER_EMAIL, '94', '771234567', 'Sales'));
        errors.put('uploadProfilePicture', uploadError(base64(PNG_HEX), 'me.png', 'image/png'));
        errors.put('changePassword', passwordError(CURRENT_PASSWORD, NEW_PASSWORD, NEW_PASSWORD));
        return errors;
    }

    @isTest
    static void showsTheCustomersOwnDetails() {
        User jane = customer();
        CustomerPortalController.Profile profile;

        Test.startTest();
        System.runAs(jane) {
            profile = CustomerPortalController.getProfile();
        }
        Test.stopTest();

        System.assertEquals('Jane', profile.firstName);
        System.assertEquals('Customer', profile.lastName);
        System.assertEquals('Jane Customer', profile.fullName);
        System.assertEquals(CUSTOMER_EMAIL, profile.email);
        System.assertEquals('94', profile.phoneCountryCode);
        System.assertEquals('771234567', profile.phoneNumber);
        System.assertEquals('Sales', profile.department);
        System.assertEquals(jane.Username, profile.username);
        System.assertEquals(null, profile.photoUrl);
        System.assertEquals(false, profile.hasPhoto);
        System.assertEquals(false, profile.emailPending);
    }

    @isTest
    static void readsPhoneNumbersWrittenInOtherWays() {
        System.assertEquals(new List<String>{ '94', '771234567' }, CustomerPortalController.splitPhone('+94 771234567'));
        System.assertEquals(new List<String>{ '91', '9876543210' }, CustomerPortalController.splitPhone('+91 98765-43210'));
        System.assertEquals(new List<String>{ '1', '5551234567' }, CustomerPortalController.splitPhone('+1 (555) 123-4567'));
        System.assertEquals(new List<String>{ '94', '771234567' }, CustomerPortalController.splitPhone('+94771234567'));
        System.assertEquals(new List<String>{ '1', '5551234567' }, CustomerPortalController.splitPhone('+15551234567'));
        System.assertEquals(new List<String>{ '91', '9876543210' }, CustomerPortalController.splitPhone('0091 9876543210'));
        System.assertEquals(new List<String>{ '94', '0771234567' }, CustomerPortalController.splitPhone('077-123 4567'));
        System.assertEquals(new List<String>{ '94', '442071234567' }, CustomerPortalController.splitPhone('+44 20 7123 4567'));
        System.assertEquals(new List<String>{ '94', '' }, CustomerPortalController.splitPhone(null));
    }

    @isTest
    static void savesTheDetailsOnTheContactAndTheLogin() {
        User jane = customer();
        String newEmail = 'janet.perera@customer-profile-test.example.com';
        CustomerPortalController.Profile profile;

        Test.startTest();
        System.runAs(jane) {
            profile = CustomerPortalController.updateProfile('  Janet ', ' Perera ', ' ' + newEmail + ' ', '+91', ' 98765-43210 ', ' Finance ');
        }
        Test.stopTest();

        Contact person = [SELECT FirstName, LastName, Email, MobilePhone, Department FROM Contact WHERE Id = :jane.ContactId];
        User login = [SELECT FirstName, LastName, Email, MobilePhone FROM User WHERE Id = :jane.Id];
        System.assertEquals('Janet', person.FirstName);
        System.assertEquals('Perera', person.LastName);
        System.assertEquals(newEmail, person.Email);
        System.assertEquals('+91 9876543210', person.MobilePhone);
        System.assertEquals('Finance', person.Department);
        System.assertEquals('Janet', login.FirstName);
        System.assertEquals('Perera', login.LastName);
        System.assertEquals('+91 9876543210', login.MobilePhone);
        // Salesforce may keep the login's old email until the customer confirms the new one; the page is told which
        System.assertEquals(!newEmail.equalsIgnoreCase(login.Email), profile.emailPending);
        System.assertEquals('Janet', profile.firstName);
        System.assertEquals('Perera', profile.lastName);
        System.assertEquals('Janet Perera', profile.fullName);
        System.assertEquals(newEmail, profile.email);
        System.assertEquals('91', profile.phoneCountryCode);
        System.assertEquals('9876543210', profile.phoneNumber);
        System.assertEquals('Finance', profile.department);
    }

    @isTest
    static void leavesTheEmailOfTheLoginAloneWhenItDidNotChange() {
        User jane = customer();
        CustomerPortalController.Profile profile;

        Test.startTest();
        System.runAs(jane) {
            profile = CustomerPortalController.updateProfile('Jane', 'Customer', CUSTOMER_EMAIL.toUpperCase(), '94', '771 234 567', null);
        }
        Test.stopTest();

        Contact person = [SELECT MobilePhone, Department FROM Contact WHERE Id = :jane.ContactId];
        System.assertEquals(false, profile.emailPending);
        System.assertEquals(CUSTOMER_EMAIL, [SELECT Email FROM User WHERE Id = :jane.Id].Email.toLowerCase());
        System.assertEquals('+94 771234567', person.MobilePhone);
        System.assertEquals(null, person.Department, 'A blank department is cleared');
    }

    @isTest
    static void checksEveryFieldBeforeSaving() {
        User jane = customer();
        Map<String, String> errors = new Map<String, String>();

        Test.startTest();
        System.runAs(jane) {
            errors.put('no first name', updateError('  ', 'Customer', CUSTOMER_EMAIL, '94', '771234567', 'Sales'));
            errors.put('long first name', updateError('J'.repeat(41), 'Customer', CUSTOMER_EMAIL, '94', '771234567', 'Sales'));
            errors.put('no last name', updateError('Jane', null, CUSTOMER_EMAIL, '94', '771234567', 'Sales'));
            errors.put('long last name', updateError('Jane', 'C'.repeat(81), CUSTOMER_EMAIL, '94', '771234567', 'Sales'));
            errors.put('no email', updateError('Jane', 'Customer', ' ', '94', '771234567', 'Sales'));
            errors.put('long email', updateError('Jane', 'Customer', 'j'.repeat(70) + '@example.com', '94', '771234567', 'Sales'));
            errors.put('bad email', updateError('Jane', 'Customer', 'jane.example.com', '94', '771234567', 'Sales'));
            errors.put('other country', updateError('Jane', 'Customer', CUSTOMER_EMAIL, '44', '771234567', 'Sales'));
            errors.put('no country', updateError('Jane', 'Customer', CUSTOMER_EMAIL, null, '771234567', 'Sales'));
            errors.put('no phone', updateError('Jane', 'Customer', CUSTOMER_EMAIL, '94', ' - ', 'Sales'));
            errors.put('short phone', updateError('Jane', 'Customer', CUSTOMER_EMAIL, '94', '12345', 'Sales'));
            errors.put('long phone', updateError('Jane', 'Customer', CUSTOMER_EMAIL, '94', '1234567890123456', 'Sales'));
            errors.put('letters', updateError('Jane', 'Customer', CUSTOMER_EMAIL, '94', '77123ABCD', 'Sales'));
            errors.put('brackets', updateError('Jane', 'Customer', CUSTOMER_EMAIL, '94', '(077) 1234567', 'Sales'));
            errors.put('long department', updateError('Jane', 'Customer', CUSTOMER_EMAIL, '94', '771234567', 'D'.repeat(81)));
        }
        Test.stopTest();

        System.assertEquals(CustomerPortalController.FIRST_NAME_REQUIRED, errors.get('no first name'));
        System.assertEquals(CustomerPortalController.FIRST_NAME_TOO_LONG, errors.get('long first name'));
        System.assertEquals(CustomerPortalController.LAST_NAME_REQUIRED, errors.get('no last name'));
        System.assertEquals(CustomerPortalController.LAST_NAME_TOO_LONG, errors.get('long last name'));
        System.assertEquals(CustomerPortalController.EMAIL_REQUIRED, errors.get('no email'));
        System.assertEquals(CustomerPortalController.EMAIL_TOO_LONG, errors.get('long email'));
        System.assertEquals(CustomerPortalController.EMAIL_INVALID, errors.get('bad email'));
        System.assertEquals(CustomerPortalController.COUNTRY_CODE_INVALID, errors.get('other country'));
        System.assertEquals(CustomerPortalController.COUNTRY_CODE_INVALID, errors.get('no country'));
        System.assertEquals(CustomerPortalController.PHONE_REQUIRED, errors.get('no phone'));
        System.assertEquals(CustomerPortalController.PHONE_INVALID, errors.get('short phone'));
        System.assertEquals(CustomerPortalController.PHONE_INVALID, errors.get('long phone'));
        System.assertEquals(CustomerPortalController.PHONE_INVALID, errors.get('letters'));
        System.assertEquals(CustomerPortalController.PHONE_INVALID, errors.get('brackets'));
        System.assertEquals(CustomerPortalController.DEPARTMENT_TOO_LONG, errors.get('long department'));
        Contact person = [SELECT FirstName, MobilePhone, Department FROM Contact WHERE Id = :jane.ContactId];
        System.assertEquals('Jane', person.FirstName, 'Nothing is saved');
        System.assertEquals('+94 771234567', person.MobilePhone);
        System.assertEquals('Sales', person.Department);
    }

    @isTest
    static void refusesGuestsAndLoginsThatAreNotCustomers() {
        User pat = partner();
        Map<String, String> guest;
        Map<String, String> channelPartner;
        Map<String, String> internal;

        Test.startTest();
        System.runAs(siteGuest()) {
            guest = errorsOfEveryCall();
        }
        System.runAs(pat) {
            channelPartner = errorsOfEveryCall();
        }
        // The admin running the test: an internal login
        internal = errorsOfEveryCall();
        Test.stopTest();

        System.assertEquals(4, guest.size());
        for (String call : guest.keySet()) {
            System.assertEquals(CustomerPortalController.NOT_SIGNED_IN, guest.get(call), 'Guest: ' + call);
            System.assertEquals(CustomerPortalController.NOT_A_CUSTOMER, channelPartner.get(call), 'Channel partner: ' + call);
            System.assertEquals(CustomerPortalController.NOT_A_CUSTOMER, internal.get(call), 'Internal user: ' + call);
        }
        System.assertEquals('Pat', [SELECT FirstName FROM Contact WHERE Email = 'pat.partner@customer-profile-test.example.com'].FirstName);
    }

    @isTest
    static void savesTheFirstPictureAsAFileOnTheAccount() {
        User jane = customer();
        Id accountId = jane.Contact.AccountId;
        String png = base64(PNG_HEX);
        CustomerPortalController.Profile profile;

        Test.startTest();
        System.runAs(jane) {
            profile = tryUpload(png, 'C:\\fakepath\\my photo!.jpeg', 'image/png');
        }
        Test.stopTest();

        if (!pictureSavedHere) {
            return;   // no site here: the save itself is checked on the live site
        }

        Id documentId = pictureIdOf(accountId);
        System.assertNotEquals(null, documentId, 'The account points to the file');
        List<ContentVersion> versions = [SELECT Title, PathOnClient FROM ContentVersion WHERE ContentDocumentId = :documentId];
        System.assertEquals(1, versions.size());
        System.assertEquals(CustomerPortalController.PICTURE_TITLE, versions[0].Title);
        System.assertEquals('my photo_.png', versions[0].PathOnClient, 'The name without its folder, with the extension of what was sent');
        ContentDocumentLink link = [
            SELECT ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :documentId AND LinkedEntityId = :accountId
        ];
        System.assertEquals('AllUsers', link.Visibility, 'Customers and internal users who see the account see it');
        System.assert(link.ShareType == 'V' || link.ShareType == 'I', 'Viewed through the account: ' + link.ShareType);
        System.assertEquals('data:image/png;base64,' + png, profile.photoUrl);
        System.assertEquals(true, profile.hasPhoto);
    }

    @isTest
    static void aNewPictureIsANewVersionOfTheSameFile() {
        User jane = customer();
        Id accountId = jane.Contact.AccountId;
        String jpeg = base64(JPEG_HEX);
        CustomerPortalController.Profile profile;

        Test.startTest();
        System.runAs(jane) {
            tryUpload(base64(PNG_HEX), 'first.png', 'image/png');
            profile = tryUpload('data:image/jpeg;base64,' + jpeg, 'Second.JPG', 'image/jpeg');
        }
        Test.stopTest();

        if (!pictureSavedHere) {
            return;   // no site here: the save itself is checked on the live site
        }

        Id documentId = pictureIdOf(accountId);
        System.assertEquals(2, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :documentId], 'Two versions of one file');
        System.assertEquals('Second.jpg',
            [SELECT PathOnClient FROM ContentVersion WHERE ContentDocumentId = :documentId AND IsLatest = true].PathOnClient);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :accountId], 'One file on the account');
        System.assertEquals('data:image/jpeg;base64,' + jpeg, profile.photoUrl);
    }

    @isTest
    static void refusesFilesThatAreNotJpegOrPngPictures() {
        User jane = customer();
        String png = base64(PNG_HEX);
        Map<String, String> errors = new Map<String, String>();

        Test.startTest();
        System.runAs(jane) {
            errors.put('pdf', uploadError(base64(PDF_HEX), 'contract.pdf', 'application/pdf'));
            errors.put('pdf sent as png', uploadError(base64(PDF_HEX), 'photo.png', 'image/png'));
            errors.put('gif', uploadError(base64(GIF_HEX), 'photo.gif', 'image/gif'));
            errors.put('no type', uploadError(png, 'photo.png', null));
            errors.put('blank', uploadError('  ', 'photo.png', 'image/png'));
            errors.put('none', uploadError(null, 'photo.png', 'image/png'));
            errors.put('empty data url', uploadError('data:image/png;base64,', 'photo.png', 'image/png'));
        }
        Test.stopTest();

        System.assertEquals(CustomerPortalController.PICTURE_WRONG_TYPE, errors.get('pdf'));
        System.assertEquals(CustomerPortalController.PICTURE_WRONG_TYPE, errors.get('pdf sent as png'));
        System.assertEquals(CustomerPortalController.PICTURE_WRONG_TYPE, errors.get('gif'));
        System.assertEquals(CustomerPortalController.PICTURE_WRONG_TYPE, errors.get('no type'));
        System.assertEquals(CustomerPortalController.PICTURE_REQUIRED, errors.get('blank'));
        System.assertEquals(CustomerPortalController.PICTURE_REQUIRED, errors.get('none'));
        System.assertEquals(CustomerPortalController.PICTURE_REQUIRED, errors.get('empty data url'));
        System.assertEquals(null, pictureIdOf(jane.Contact.AccountId), 'Nothing is saved');
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :jane.Contact.AccountId]);
    }

    @isTest
    static void refusesPicturesLargerThanTheLimit() {
        User jane = customer();
        // 31 bytes stand for the 2 MB: at most 44 characters of Base64
        CustomerPortalController.maxPictureBytes = 31;
        Map<String, String> errors = new Map<String, String>();

        Test.startTest();
        System.runAs(jane) {
            errors.put('far too long', uploadError(pngOfSize(120), 'big.png', 'image/png'));
            errors.put('too long', uploadError(pngOfSize(40), 'big.png', 'image/png'));
            errors.put('one byte over', uploadError(pngOfSize(32), 'big.png', 'image/png'));
            errors.put('at the limit', uploadError(pngOfSize(31), 'fits.png', 'image/png'));
        }
        Test.stopTest();

        if (!pictureSavedHere) {
            return;   // no site here: the save itself is checked on the live site
        }

        System.assertEquals(CustomerPortalController.PICTURE_TOO_BIG, errors.get('far too long'));
        System.assertEquals(CustomerPortalController.PICTURE_TOO_BIG, errors.get('too long'));
        System.assertEquals(CustomerPortalController.PICTURE_TOO_BIG, errors.get('one byte over'));
        System.assertEquals(null, errors.get('at the limit'));
        Id documentId = pictureIdOf(jane.Contact.AccountId);
        System.assertEquals(1, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :documentId], 'Only the picture that fits');
    }

    @isTest
    static void startsANewFileWhenTheAccountPointsToNoFile() {
        User jane = customer();
        Id accountId = jane.Contact.AccountId;
        String png = base64(PNG_HEX);
        update new Account(Id = accountId, Profile_Picture_Document_Id__c = '069000000000000AAA');
        CustomerPortalController.Profile before;
        CustomerPortalController.Profile afterMissingFile;
        CustomerPortalController.Profile afterNoId;
        Id firstFile;

        Test.startTest();
        System.runAs(jane) {
            before = CustomerPortalController.getProfile();
            afterMissingFile = tryUpload(png, 'me.png', 'image/png');
        }
        firstFile = pictureIdOf(accountId);
        update new Account(Id = accountId, Profile_Picture_Document_Id__c = 'not a file');
        System.runAs(jane) {
            afterNoId = tryUpload(png, 'me.png', 'image/png');
        }
        Test.stopTest();

        if (!pictureSavedHere) {
            return;   // no site here: the save itself is checked on the live site
        }

        System.assertEquals(null, before.photoUrl, 'No file behind the Id');
        System.assertNotEquals(null, firstFile);
        System.assertNotEquals('069000000000000AAA', String.valueOf(firstFile));
        System.assertEquals('data:image/png;base64,' + png, afterMissingFile.photoUrl);
        System.assertNotEquals(firstFile, pictureIdOf(accountId), 'A new file');
        System.assertEquals('data:image/png;base64,' + png, afterNoId.photoUrl);
    }

    @isTest
    static void savesThePictureWhenTheAccountPointsToAFileOfSomebodyElse() {
        User jane = customer();
        Id accountId = jane.Contact.AccountId;
        ContentVersion officeFile = new ContentVersion(Title = 'Photo from the office', PathOnClient = 'office.png',
            VersionData = EncodingUtil.convertFromHex(PNG_HEX), FirstPublishLocationId = accountId);
        insert officeFile;
        update new Account(Id = accountId, Profile_Picture_Document_Id__c = documentOf(officeFile));
        String jpeg = base64(JPEG_HEX);
        CustomerPortalController.Profile profile;

        Test.startTest();
        System.runAs(jane) {
            profile = tryUpload(jpeg, 'mine.jpg', 'image/jpeg');
        }
        Test.stopTest();

        if (!pictureSavedHere) {
            return;   // no site here: the save itself is checked on the live site
        }

        // A new version of that file, or a new file of the customer's when Salesforce does not let them change it
        Id documentId = pictureIdOf(accountId);
        System.assertEquals('mine.jpg',
            [SELECT PathOnClient FROM ContentVersion WHERE ContentDocumentId = :documentId AND IsLatest = true].PathOnClient);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :documentId AND LinkedEntityId = :accountId]);
        System.assertEquals('data:image/jpeg;base64,' + jpeg, profile.photoUrl);
    }

    @isTest
    static void ignoresAFileThatIsNotOnTheAccount() {
        User jane = customer();
        Id accountId = jane.Contact.AccountId;
        // A picture in the test user's own files, not linked to the customer's account
        ContentVersion elsewhere = new ContentVersion(Title = 'Somebody else', PathOnClient = 'other.png',
            VersionData = EncodingUtil.convertFromHex(PNG_HEX));
        insert elsewhere;
        Id otherDocument = documentOf(elsewhere);
        update new Account(Id = accountId, Profile_Picture_Document_Id__c = otherDocument);
        CustomerPortalController.Profile before;
        CustomerPortalController.Profile after;

        Test.startTest();
        System.runAs(jane) {
            before = CustomerPortalController.getProfile();
            after = tryUpload(base64(PNG_HEX), 'me.png', 'image/png');
        }
        Test.stopTest();

        if (!pictureSavedHere) {
            return;   // no site here: the save itself is checked on the live site
        }

        System.assertEquals(null, before.photoUrl, 'a file that is not on the account is never shown');
        Id documentId = pictureIdOf(accountId);
        System.assertNotEquals(otherDocument, documentId, 'the upload makes a new file instead of a version of the other one');
        System.assertEquals(1, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :otherDocument]);
        System.assertNotEquals(null, after.photoUrl);
    }

    @isTest
    static void showsTheDefaultAvatarWhenThePictureCannotBeShown() {
        User jane = customer();
        Id accountId = jane.Contact.AccountId;
        ContentVersion contract = new ContentVersion(Title = 'Contract', PathOnClient = 'contract.pdf',
            VersionData = EncodingUtil.convertFromHex(PDF_HEX), FirstPublishLocationId = accountId);
        insert contract;
        update new Account(Id = accountId, Profile_Picture_Document_Id__c = documentOf(contract));
        CustomerPortalController.Profile notAPicture;
        CustomerPortalController.Profile tooLarge;

        Test.startTest();
        System.runAs(jane) {
            notAPicture = CustomerPortalController.getProfile();
            tryUpload(base64(PNG_HEX), 'me.png', 'image/png');
            CustomerPortalController.maxInlineBytes = 10;
            tooLarge = CustomerPortalController.getProfile();
        }
        Test.stopTest();

        if (!pictureSavedHere) {
            return;   // no site here: the save itself is checked on the live site
        }

        System.assertEquals(null, notAPicture.photoUrl, 'A file that is not a picture');
        System.assertEquals(false, notAPicture.hasPhoto);
        System.assertEquals(null, tooLarge.photoUrl, 'A picture larger than the page gets inline');
        System.assertEquals(false, tooLarge.hasPhoto);
        System.assertNotEquals(null, pictureIdOf(accountId), 'The file stays the account picture');
        System.assertEquals(null, CustomerPortalController.photoUrlFor(null));
    }

    @isTest
    static void linksThePictureToTheAccountForEverybodyWhoSeesTheAccount() {
        Id accountId = customer().Contact.AccountId;
        // A file that is not on the account yet, and one on the account that only internal users see
        ContentVersion loose = new ContentVersion(Title = 'Loose', PathOnClient = 'loose.png', VersionData = EncodingUtil.convertFromHex(PNG_HEX));
        ContentVersion internalOnly = new ContentVersion(Title = 'Internal', PathOnClient = 'internal.png',
            VersionData = EncodingUtil.convertFromHex(PNG_HEX), FirstPublishLocationId = accountId);
        insert new List<ContentVersion>{ loose, internalOnly };
        Id looseId = documentOf(loose);
        Id internalId = documentOf(internalOnly);
        Id internalLinkId = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId = :internalId AND LinkedEntityId = :accountId].Id;
        try {
            update new ContentDocumentLink(Id = internalLinkId, Visibility = 'InternalUsers');
        } catch (DmlException e) {
            // Then the link already is visible to all, which the assertion below accepts as well
        }

        Test.startTest();
        CustomerPortalController.ensureAccountLink(looseId, accountId);
        CustomerPortalController.ensureAccountLink(looseId, accountId);
        CustomerPortalController.ensureAccountLink(internalId, accountId);
        Test.stopTest();

        List<ContentDocumentLink> looseLinks = [
            SELECT ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :looseId AND LinkedEntityId = :accountId
        ];
        System.assertEquals(1, looseLinks.size(), 'Linked once');
        System.assertEquals('V', looseLinks[0].ShareType);
        System.assertEquals('AllUsers', looseLinks[0].Visibility);
        System.assertEquals('AllUsers',
            [SELECT Visibility FROM ContentDocumentLink WHERE ContentDocumentId = :internalId AND LinkedEntityId = :accountId].Visibility);
    }

    @isTest
    static void keepsASafeFileName() {
        System.assertEquals('my photo_.png', CustomerPortalController.fileNameFor('C:\\fakepath\\my photo!.jpeg', 'png'));
        System.assertEquals('passwd.jpg', CustomerPortalController.fileNameFor('../../etc/passwd', 'jpg'));
        System.assertEquals('profile-picture.jpg', CustomerPortalController.fileNameFor(null, 'jpg'));
        System.assertEquals('profile-picture.png', CustomerPortalController.fileNameFor('.png', 'png'));
        System.assertEquals(84, CustomerPortalController.fileNameFor('a'.repeat(300) + '.png', 'png').length());
    }

    @isTest
    static void changesThePasswordThroughTheSite() {
        User jane = customer();
        FakeSite fake = fakeSite();
        String message;

        Test.startTest();
        System.runAs(jane) {
            message = passwordError(CURRENT_PASSWORD, NEW_PASSWORD, NEW_PASSWORD);
        }
        Test.stopTest();

        System.assertEquals(null, message);
        System.assertEquals(new List<String>{ NEW_PASSWORD + '|' + NEW_PASSWORD + '|' + CURRENT_PASSWORD }, fake.calls,
            'The new password, its confirmation, then the current one');
    }

    @isTest
    static void checksThePasswordRulesBeforeAskingSalesforce() {
        User jane = customer();
        FakeSite fake = fakeSite();
        Map<String, String> errors = new Map<String, String>();

        Test.startTest();
        System.runAs(jane) {
            errors.put('no current', passwordError('', NEW_PASSWORD, NEW_PASSWORD));
            errors.put('no confirmation', passwordError(CURRENT_PASSWORD, NEW_PASSWORD, null));
            errors.put('mismatch', passwordError(CURRENT_PASSWORD, NEW_PASSWORD, NEW_PASSWORD + 'x'));
            errors.put('other case', passwordError(CURRENT_PASSWORD, NEW_PASSWORD, NEW_PASSWORD.toLowerCase()));
            errors.put('short', passwordError(CURRENT_PASSWORD, 'Ab#12', 'Ab#12'));
            errors.put('no number', passwordError(CURRENT_PASSWORD, 'Password#', 'Password#'));
            errors.put('no letter', passwordError(CURRENT_PASSWORD, '12345678#', '12345678#'));
            errors.put('same', passwordError(CURRENT_PASSWORD, CURRENT_PASSWORD, CURRENT_PASSWORD));
        }
        Test.stopTest();

        System.assertEquals(CustomerPortalController.PASSWORD_REQUIRED, errors.get('no current'));
        System.assertEquals(CustomerPortalController.PASSWORD_REQUIRED, errors.get('no confirmation'));
        System.assertEquals(CustomerPortalController.PASSWORD_MISMATCH, errors.get('mismatch'));
        System.assertEquals(CustomerPortalController.PASSWORD_MISMATCH, errors.get('other case'));
        System.assertEquals(CustomerPortalController.PASSWORD_TOO_WEAK, errors.get('short'));
        System.assertEquals(CustomerPortalController.PASSWORD_TOO_WEAK, errors.get('no number'));
        System.assertEquals(CustomerPortalController.PASSWORD_TOO_WEAK, errors.get('no letter'));
        System.assertEquals(CustomerPortalController.PASSWORD_SAME, errors.get('same'));
        System.assertEquals(0, fake.calls.size(), 'Salesforce is not asked');
    }

    @isTest
    static void saysSoWhenSalesforceDoesNotChangeThePassword() {
        User jane = customer();
        FakeSite fake = fakeSite();
        String noAnswer;
        String refused;

        Test.startTest();
        System.runAs(jane) {
            fake.answer = null;
            noAnswer = passwordError(CURRENT_PASSWORD, NEW_PASSWORD, NEW_PASSWORD);
            fake.fails = true;
            refused = passwordError(CURRENT_PASSWORD, NEW_PASSWORD, NEW_PASSWORD);
        }
        Test.stopTest();

        System.assertEquals(CustomerPortalController.PASSWORD_NOT_CHANGED, noAnswer, 'No answer and no password change');
        System.assertEquals(CustomerPortalController.PASSWORD_NOT_CHANGED, refused);
        System.assert(!refused.contains(CURRENT_PASSWORD) && !refused.contains(NEW_PASSWORD), 'The message never shows a password');
        System.assertEquals(2, fake.calls.size());
    }

    @isTest
    static void theRealSiteCallChangesThePasswordOrSaysItDidNot() {
        // Salesforce's own Site.changePassword: a test has no site session, so it normally changes nothing
        User jane = customer();
        String message;

        Test.startTest();
        System.runAs(jane) {
            message = passwordError(CURRENT_PASSWORD, NEW_PASSWORD, NEW_PASSWORD);
        }
        Test.stopTest();

        System.assert(message == null || message == CustomerPortalController.PASSWORD_NOT_CHANGED, message);
    }

    @isTest
    static void theHeaderShowsTheCustomersNameAndPicture() {
        User jane = customer();
        String png = base64(PNG_HEX);
        CustomerPortalController.HeaderData before;
        CustomerPortalController.PortalData after;

        Test.startTest();
        System.runAs(jane) {
            before = CustomerPortalController.getHeaderData();
            tryUpload(png, 'me.png', 'image/png');
            after = CustomerPortalController.getPortalData();
        }
        // An internal login (the admin running the test) has no customer account and so no picture
        CustomerPortalController.HeaderData internal = CustomerPortalController.getHeaderData();
        Test.stopTest();

        if (!pictureSavedHere) {
            return;   // no site here: the save itself is checked on the live site
        }

        System.assertEquals(jane.Name, before.userName);
        System.assertEquals('Customer', before.userRole);
        System.assertEquals(null, before.avatarUrl);
        System.assertEquals(jane.Name, after.headerData.userName);
        System.assertEquals('data:image/png;base64,' + png, after.headerData.avatarUrl);
        System.assertEquals(15, after.menuItems.size());
        System.assertEquals([SELECT Name FROM User WHERE Id = :UserInfo.getUserId()].Name, internal.userName);
        System.assertEquals(null, internal.avatarUrl);
    }
}