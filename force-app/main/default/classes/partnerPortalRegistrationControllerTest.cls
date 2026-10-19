@isTest
private class partnerPortalRegistrationControllerTest {

    private static final String PENDING = 'Pending';
    // The org's channel partner record type, as its Partner Registration Setting names it
    private static final String PARTNER_TYPE = Partner_Registration_Setting__mdt.getInstance(
        partnerPortalRegistrationController.SETTINGS_RECORD).Account_Record_Type__c;
    private static final String PDF_DATA = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 a small test document'));
    private static final String PNG_DATA = EncodingUtil.base64Encode(EncodingUtil.convertFromHex('89504E470D0A1A0A0000000D49484452'));
    private static final String JPEG_DATA = EncodingUtil.base64Encode(EncodingUtil.convertFromHex('FFD8FFE000104A464946'));

    // ---------- a registration setup of the tests' own, so they do not depend on how the org's form is configured ----------

    private static void useTestSetup() {
        useTestSetup(new Map<String, Object>());
    }

    private static void useTestSetup(Map<String, Object> settingOverrides) {
        Map<String, Object> values = new Map<String, Object>{
            'DeveloperName' => 'Default',
            'MasterLabel' => 'Default',
            'Account_Record_Type__c' => PARTNER_TYPE,
            'Registration_Status__c' => PENDING,
            'Registration_Type_Field__c' => 'Registration_Type__c',
            'Record_Owner__c' => UserInfo.getUserName(),
            'Allowed_File_Types__c' => 'pdf, .PNG',
            'Max_File_Size_MB__c' => 1,
            'Max_Files__c' => 2,
            'Upload_Window_Minutes__c' => 30,
            'Approval_Process__c' => 'Partner_Onboarding_Approval',
            'Rejected_Status__c' => 'Rejected'
        };
        values.putAll(settingOverrides);
        partnerPortalRegistrationController.setting = (Partner_Registration_Setting__mdt) JSON.deserialize(
            JSON.serialize(values),
            Partner_Registration_Setting__mdt.class
        );
        partnerPortalRegistrationController.fieldRecords = new List<Partner_Registration_Field__mdt>{
            field('Company_Name', 'Company', 'businessName', 'Text', true, 'Name, Business_Name__c', null),
            field('Company_Contact', 'Company', 'contactPerson', 'Text', true, null, 'Name'),
            field('Company_Email', 'Company', 'email', 'Email', true, 'Email__c', 'Email'),
            field('Company_Phone', 'Company', 'phone', 'Phone', false, 'Phone', 'Phone'),
            field('Company_Project', 'Company', 'project', 'Project', false, 'Project__c', null),
            documentsField('Company_Documents', 'Company', true, 'BR, VAT Certificate'),
            field('Individual_Name', 'Individual', 'fullName', 'Text', true, 'Name', 'Name'),
            field('Individual_Email', 'Individual', 'email', 'Email', true, 'Email__c', 'Email'),
            field('Individual_NIC', 'Individual', 'nic', 'Text', true, 'NIC_Number__c', null),
            documentsField('Individual_Documents', 'Individual', false, 'NIC, TIN and passport'),
            hiddenField('All_Flag', 'Portal_Registration_User__c', 'true')
        };
    }

    private static Partner_Registration_Field__mdt field(String developerName, String registrationType, String inputName,
            String inputType, Boolean required, String accountFields, String contactFields) {
        return record(new Map<String, Object>{
            'DeveloperName' => developerName,
            'MasterLabel' => developerName,
            'Registration_Type__c' => registrationType,
            'Input_Name__c' => inputName,
            'Input_Type__c' => inputType,
            'Field_Label__c' => inputName + ' label',
            'Required__c' => required,
            'Account_Field__c' => accountFields,
            'Contact_Field__c' => contactFields,
            'Active__c' => true
        });
    }

    // A Documents input whose files go to a Document category's SharePoint folder (when the record type has categories)
    private static Partner_Registration_Field__mdt documentsField(String developerName, String registrationType, Boolean required,
            String documentCategory) {
        return record(new Map<String, Object>{
            'DeveloperName' => developerName,
            'MasterLabel' => developerName,
            'Registration_Type__c' => registrationType,
            'Input_Name__c' => 'documents',
            'Input_Type__c' => 'Documents',
            'Field_Label__c' => 'documents label',
            'Required__c' => required,
            'Document_Category__c' => documentCategory,
            'Active__c' => true
        });
    }

    private static Partner_Registration_Field__mdt hiddenField(String developerName, String accountFields, String defaultValue) {
        return record(new Map<String, Object>{
            'DeveloperName' => developerName,
            'MasterLabel' => developerName,
            'Input_Type__c' => 'Hidden',
            'Account_Field__c' => accountFields,
            'Default_Value__c' => defaultValue,
            'Active__c' => true
        });
    }

    private static Partner_Registration_Field__mdt record(Map<String, Object> values) {
        return (Partner_Registration_Field__mdt) JSON.deserialize(JSON.serialize(values), Partner_Registration_Field__mdt.class);
    }

    private static Id partnerTypeId() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(PARTNER_TYPE).getRecordTypeId();
    }

    // Another active Account record type (customers), or null when the org has none
    private static Id otherAccountTypeId() {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isActive() && !info.isMaster() && info.getRecordTypeId() != partnerTypeId()) {
                return info.getRecordTypeId();
            }
        }
        return null;
    }

    private static User guest() {
        return [SELECT Id FROM User WHERE UserType = 'Guest' AND Profile.Name = 'Partner Portal Profile' AND IsActive = true LIMIT 1];
    }

    private static Map<String, String> companyValues(String email) {
        return new Map<String, String>{
            'businessName' => 'Harbour Realty',
            'contactPerson' => 'Kamal Perera',
            'email' => email,
            'phone' => '+94 77 123 4567'
        };
    }

    // Documents as the page sends them with a registration: the first carries its content, which suits its name
    private static List<partnerPortalRegistrationController.DocumentInfo> documents(List<String> names, Long size) {
        List<partnerPortalRegistrationController.DocumentInfo> documents = declaredOnly(names, size);
        if (!documents.isEmpty()) {
            String name = documents[0].name.toLowerCase();
            documents[0].base64Data = name.endsWith('.png') ? PNG_DATA
                : (name.endsWith('.jpg') || name.endsWith('.jpeg') ? JPEG_DATA : PDF_DATA);
        }
        return documents;
    }

    // Documents without any content: only their names and sizes, as a hand-made request could send
    private static List<partnerPortalRegistrationController.DocumentInfo> declaredOnly(List<String> names, Long size) {
        List<partnerPortalRegistrationController.DocumentInfo> documents = new List<partnerPortalRegistrationController.DocumentInfo>();
        for (String name : names) {
            partnerPortalRegistrationController.DocumentInfo document = new partnerPortalRegistrationController.DocumentInfo();
            document.name = name;
            document.size = size;
            documents.add(document);
        }
        return documents;
    }

    // The error shown to the user; a call that was not refused says so
    private static String uploadError(String ticket, String fileName, String data) {
        try {
            partnerPortalRegistrationController.uploadDocument(ticket, fileName, data);
            return 'Not refused';
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    private static String formError() {
        try {
            partnerPortalRegistrationController.getRegistrationForm();
            return 'Not refused';
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    private static String registerError(String registrationType, Map<String, String> values) {
        try {
            return 'Not refused: ' + partnerPortalRegistrationController.register(registrationType, values, documents(new List<String>{ 'BR.pdf' }, 100)).status;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    // ---------- the form ----------

    @isTest
    static void formListsEachTypesInputsWithTheirRules() {
        useTestSetup();
        insert new List<Project__c>{
            TestRecordDefaults.project('Skyline Towers', true),
            TestRecordDefaults.project('Old Tower', false)
        };

        Test.startTest();
        partnerPortalRegistrationController.RegistrationForm form = partnerPortalRegistrationController.getRegistrationForm();
        Test.stopTest();

        System.assertEquals(2, form.types.size());
        partnerPortalRegistrationController.RegistrationType company = form.types[0];
        System.assertEquals('Company', company.value, 'Types follow the Registration Type picklist');
        System.assertEquals('Individual', form.types[1].value);
        List<String> inputs = new List<String>();
        for (partnerPortalRegistrationController.FormField field : company.fields) {
            inputs.add(field.name + ':' + field.type);
        }
        System.assertEquals('businessName:text,contactPerson:text,email:email,phone:tel,project:project,documents:upload',
            String.join(inputs, ','), 'Hidden fields are not shown');
        System.assertEquals('businessName label', company.fields[0].label);
        System.assertEquals(true, company.fields[0].required);
        System.assertEquals(Account.Business_Name__c.getDescribe().getLength(), company.fields[0].maxLength,
            'The shortest of the fields that store the value');
        System.assertEquals(Contact.FirstName.getDescribe().getLength() + 1 + Contact.LastName.getDescribe().getLength(),
            company.fields[1].maxLength, 'A split name fits both name fields');
        System.assertEquals(1, company.fields[4].options.size(), 'Only active projects are offered');
        System.assertEquals('Skyline Towers', company.fields[4].options[0].label);
        System.assertEquals(new List<String>{ 'pdf', 'png' }, form.fileTypes);
        System.assertEquals(1, form.maxFileSizeMb.intValue());
        System.assertEquals(2, form.maxFiles);
    }

    @isTest
    static void explainsWhatIsWrongWithTheSetup() {
        useTestSetup();
        partnerPortalRegistrationController.fieldRecords.add(field('Company_Bad', 'Company', 'bad', 'Text', false, 'No_Such_Field__c', null));
        String unknownField = formError();

        partnerPortalRegistrationController.fieldRecords[partnerPortalRegistrationController.fieldRecords.size() - 1] =
            field('Company_Bad', 'Company', 'bad', 'Text', false, 'CreatedDate', null);
        String readOnlyField = formError();

        partnerPortalRegistrationController.fieldRecords[partnerPortalRegistrationController.fieldRecords.size() - 1] =
            field('Company_Bad', 'Company', 'bad', 'Slider', false, null, null);
        String unknownType = formError();

        partnerPortalRegistrationController.fieldRecords[partnerPortalRegistrationController.fieldRecords.size() - 1] =
            field('Company_Bad', 'Company', 'email', 'Text', false, null, null);
        String repeatedName = formError();

        useTestSetup(new Map<String, Object>{ 'Record_Owner__c' => 'nobody@registration-test.example.com.invalid' });
        String unknownOwner = registerError('Company', companyValues('owner@registration-test.example.com'));

        useTestSetup(new Map<String, Object>{ 'Account_Record_Type__c' => 'No_Such_Record_Type' });
        String unknownRecordType = registerError('Company', companyValues('type@registration-test.example.com'));

        useTestSetup(new Map<String, Object>{ 'Account_Record_Type__c' => null });
        String noRecordType = registerError('Company', companyValues('notype@registration-test.example.com'));

        System.assert(unknownField.contains('Company_Bad') && unknownField.contains('No_Such_Field__c'), unknownField);
        System.assert(readOnlyField.contains('cannot be filled in'), readOnlyField);
        System.assert(unknownType.contains('unknown Input Type'), unknownType);
        System.assert(repeatedName.contains('Input Name email'), repeatedName);
        System.assert(unknownOwner.contains('Record Owner'), unknownOwner);
        System.assert(unknownRecordType.contains('No_Such_Record_Type'), unknownRecordType);
        System.assert(noRecordType.contains('Account Record Type'), 'A registration never goes without the channel partner record type: ' + noRecordType);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Email__c LIKE '%@registration-test.example.com']);
    }

    // ---------- registering ----------

    @isTest
    static void registersACompanyAndItsContactAsTheSiteGuest() {
        useTestSetup();
        Project__c project = TestRecordDefaults.project('Skyline Towers', true);
        insert project;
        Map<String, String> values = companyValues('hello@harbour-realty.example.com');
        values.put('project', project.Id);
        values.put('businessName', '  Harbour Realty  ');
        partnerPortalRegistrationController.RegistrationResult result;

        Test.startTest();
        System.runAs(guest()) {
            result = partnerPortalRegistrationController.register('company', values, documents(new List<String>{ 'BR.pdf' }, 2048));
        }
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.REGISTERED, result.status, result.fieldErrors);
        System.assert(String.isNotBlank(result.ticket));
        Account account = [
            SELECT Name, Business_Name__c, Email__c, Phone, Project__c, OwnerId, Onboarding_Status__c, Registration_Type__c,
                Portal_Registration_User__c, RecordTypeId,
                (SELECT FirstName, LastName, Email, Phone, OwnerId FROM Contacts)
            FROM Account
            WHERE Email__c = 'hello@harbour-realty.example.com'
        ];
        System.assertEquals('Harbour Realty', account.Name, 'Values are trimmed');
        System.assertEquals('Harbour Realty', account.Business_Name__c, 'One value can fill several fields');
        System.assertEquals('+94 77 123 4567', account.Phone);
        System.assertEquals(project.Id, account.Project__c);
        System.assertEquals(UserInfo.getUserId(), account.OwnerId, 'The Record Owner of the settings');
        System.assertEquals(partnerTypeId(), account.RecordTypeId, 'Every registration is a channel partner account');
        System.assertEquals(PENDING, account.Onboarding_Status__c);
        System.assertEquals('Company', account.Registration_Type__c, 'The type as the picklist spells it');
        System.assertEquals(true, account.Portal_Registration_User__c, 'Hidden fields write their default value');
        System.assertEquals(1, account.Contacts.size());
        Contact contact = account.Contacts[0];
        System.assertEquals('Kamal', contact.FirstName);
        System.assertEquals('Perera', contact.LastName);
        System.assertEquals('hello@harbour-realty.example.com', contact.Email);
        System.assertEquals('+94 77 123 4567', contact.Phone);
        System.assertEquals(UserInfo.getUserId(), contact.OwnerId);
        List<ContentDocumentLink> files = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN (SELECT Id FROM Account WHERE Email__c = 'hello@harbour-realty.example.com')
        ];
        System.assertEquals(1, files.size(), 'The first document is saved with the registration');
        System.assertEquals('BR', files[0].ContentDocument.Title);
        ProcessInstance request = [
            SELECT Status, SubmittedById, ProcessDefinition.DeveloperName, (SELECT ActorId FROM Workitems)
            FROM ProcessInstance WHERE TargetObjectId = :account.Id
        ];
        System.assertEquals('Pending', request.Status, 'Sent straight to the CP Manager');
        System.assertEquals('Partner_Onboarding_Approval', request.ProcessDefinition.DeveloperName, 'The Approval Process of the settings');
        System.assertEquals(UserInfo.getUserId(), request.SubmittedById, 'On behalf of the record owner');
        System.assertEquals(1, request.Workitems.size(), 'Waiting for the approver');
    }

    // Without an Approval Process in the settings the registration is saved and nothing is submitted; when the
    // process cannot take it, nothing is saved and the partner is asked to try again
    @isTest
    static void submitsTheRegistrationOnlyToTheConfiguredApprovalProcess() {
        useTestSetup(new Map<String, Object>{ 'Approval_Process__c' => null });
        partnerPortalRegistrationController.RegistrationResult withoutProcess;
        System.runAs(guest()) {
            withoutProcess = partnerPortalRegistrationController.register('company', companyValues('no-process@harbour-realty.example.com'),
                documents(new List<String>{ 'BR.pdf' }, 2048));
        }
        System.assertEquals(partnerPortalRegistrationController.REGISTERED, withoutProcess.status, withoutProcess.fieldErrors);
        System.assertEquals(0, [SELECT COUNT() FROM ProcessInstance], 'Nothing to approve');

        useTestSetup(new Map<String, Object>{ 'Approval_Process__c' => 'No_Such_Approval_Process' });
        String refusal;
        System.runAs(guest()) {
            try {
                partnerPortalRegistrationController.register('company', companyValues('unknown-process@harbour-realty.example.com'),
                    documents(new List<String>{ 'BR.pdf' }, 2048));
            } catch (AuraHandledException e) {
                refusal = e.getMessage();
            }
        }
        System.assertEquals('Your registration could not be sent for approval right now. Please try again in a few minutes.', refusal);
    }

    @isTest
    static void registersAnIndividualWithALongName() {
        useTestSetup();
        String fullName = 'Herath Mudiyanselage Ranjith Bandara Wijesinghe Perera';
        partnerPortalRegistrationController.RegistrationResult result;

        Test.startTest();
        System.runAs(guest()) {
            result = partnerPortalRegistrationController.register('Individual', new Map<String, String>{
                'fullName' => fullName,
                'email' => 'ranjith@registration-test.example.com',
                'nic' => '199012345678'
            }, null);
        }
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.REGISTERED, result.status, result.fieldErrors);
        Account account = [
            SELECT Name, NIC_Number__c, Registration_Type__c, (SELECT FirstName, LastName FROM Contacts)
            FROM Account
            WHERE Email__c = 'ranjith@registration-test.example.com'
        ];
        System.assertEquals(fullName, account.Name);
        System.assertEquals('199012345678', account.NIC_Number__c);
        System.assertEquals('Individual', account.Registration_Type__c);
        System.assertEquals('Herath Mudiyanselage Ranjith Bandara', account.Contacts[0].FirstName, 'As many words as fit');
        System.assertEquals('Wijesinghe Perera', account.Contacts[0].LastName);
    }

    @isTest
    static void reportsEveryProblemWithoutSavingAnything() {
        useTestSetup();
        partnerPortalRegistrationController.RegistrationResult result;

        Test.startTest();
        System.runAs(guest()) {
            result = partnerPortalRegistrationController.register('Company', new Map<String, String>{
                'businessName' => 'x'.repeat(Account.Business_Name__c.getDescribe().getLength() + 1),
                'contactPerson' => '   ',
                'email' => 'not-an-email',
                'phone' => '12345',
                'project' => UserInfo.getUserId()
            }, null);
        }
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.INVALID, result.status);
        System.assertEquals(null, result.ticket);
        System.assert(result.fieldErrors.get('businessName').contains('characters or fewer'), result.fieldErrors);
        System.assertEquals('This field is required.', result.fieldErrors.get('contactPerson'));
        System.assertEquals('Enter a valid email address.', result.fieldErrors.get('email'));
        System.assertEquals('Enter a valid phone number.', result.fieldErrors.get('phone'));
        System.assertEquals('Choose a project from the list.', result.fieldErrors.get('project'));
        System.assertEquals('Upload at least one document.', result.fieldErrors.get('documents'));
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name LIKE 'xxxx%']);
        System.assertEquals('Choose a registration type.', registerError('Partnership', companyValues('a@b.example.com')));
    }

    @isTest
    static void checksTheDocumentsBeforeSaving() {
        useTestSetup();
        Map<String, String> values = companyValues('docs@registration-test.example.com');

        Test.startTest();
        String wrongType = partnerPortalRegistrationController.register('Company', values,
            documents(new List<String>{ 'scan.docx' }, 100)).fieldErrors.get('documents');
        String tooLarge = partnerPortalRegistrationController.register('Company', values,
            documents(new List<String>{ 'big.pdf' }, 2 * 1024 * 1024)).fieldErrors.get('documents');
        String tooMany = partnerPortalRegistrationController.register('Company', values,
            documents(new List<String>{ 'a.pdf', 'b.pdf', 'c.png' }, 100)).fieldErrors.get('documents');
        Test.stopTest();

        System.assertEquals('scan.docx is not a PDF or PNG file.', wrongType);
        System.assertEquals('big.pdf is larger than 1 MB.', tooLarge);
        System.assertEquals('Upload up to 2 documents.', tooMany);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Email__c = 'docs@registration-test.example.com']);
    }

    @isTest
    static void aRequiredUploadNeedsADocumentSavedWithTheRegistration() {
        useTestSetup();

        Test.startTest();
        partnerPortalRegistrationController.RegistrationResult result =
            partnerPortalRegistrationController.register('Company', companyValues('nodocs@registration-test.example.com'),
                declaredOnly(new List<String>{ 'BR.pdf', 'VAT.png' }, 100));
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.INVALID, result.status,
            'Naming documents without sending one is not enough: it could leave a registration without any');
        System.assertEquals('Upload at least one document.', result.fieldErrors.get('documents'));
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Email__c = 'nodocs@registration-test.example.com']);
    }

    @isTest
    static void refusesADamagedFirstDocumentWithoutSavingAnything() {
        useTestSetup();
        List<partnerPortalRegistrationController.DocumentInfo> renamed = documents(new List<String>{ 'NIC.pdf' }, 100);
        renamed[0].base64Data = PNG_DATA;
        List<partnerPortalRegistrationController.DocumentInfo> unreadable = documents(new List<String>{ 'NIC.pdf' }, 100);
        unreadable[0].base64Data = '%%%';

        Test.startTest();
        String renamedError = partnerPortalRegistrationController.register('Company',
            companyValues('damaged@registration-test.example.com'), renamed).fieldErrors.get('documents');
        String unreadableError = partnerPortalRegistrationController.register('Company',
            companyValues('damaged@registration-test.example.com'), unreadable).fieldErrors.get('documents');
        Test.stopTest();

        System.assertEquals('NIC.pdf is not a valid PDF file.', renamedError);
        System.assert(unreadableError != null && unreadableError.startsWith('NIC.pdf'), unreadableError);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Email__c = 'damaged@registration-test.example.com']);
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE Email = 'damaged@registration-test.example.com']);
    }

    @isTest
    static void refusesAnEmailWaitingForApproval() {
        useTestSetup();
        insert new Account(Name = 'Harbour Realty', Email__c = 'pending@registration-test.example.com', Onboarding_Status__c = PENDING,
            RecordTypeId = partnerTypeId());
        Map<String, String> values = companyValues('Pending@Registration-Test.example.com');
        values.remove('businessName');

        Test.startTest();
        partnerPortalRegistrationController.RegistrationResult result =
            partnerPortalRegistrationController.register('Company', values, documents(new List<String>{ 'BR.pdf' }, 100));
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.INVALID, result.status);
        System.assertEquals(true, result.pendingRegistration);
        System.assertEquals('A registration with this email is already waiting for approval.', result.fieldErrors.get('email'),
            'Emails match in any case');
        System.assertEquals('This field is required.', result.fieldErrors.get('businessName'), 'Shown together with the other problems');
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Email__c = 'pending@registration-test.example.com']);
    }

    // An executive is added by their channel partner and approved by JKP; they never register themselves
    @isTest
    static void refusesAnExecutivesEmail() {
        useTestSetup();
        Account head = new Account(Name = 'Nazir Partner', RecordTypeId = partnerTypeId());
        insert head;
        insert new Account(Name = 'Amal Perera', Email__c = 'executive@registration-test.example.com', Onboarding_Status__c = PENDING,
            RecordTypeId = partnerTypeId(), Channel_Head__c = head.Id);

        Test.startTest();
        partnerPortalRegistrationController.RegistrationResult result =
            partnerPortalRegistrationController.register('Company', companyValues('Executive@Registration-Test.example.com'),
                documents(new List<String>{ 'BR.pdf' }, 100));
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.INVALID, result.status);
        System.assertEquals(false, result.pendingRegistration, 'They never registered, so no registration of theirs is pending');
        System.assertEquals('Your channel partner has already added you, so you don\'t need to register. '
            + 'You will receive your login details by email once John Keells Properties approves you.', result.fieldErrors.get('email'));
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Harbour Realty']);
    }

    @isTest
    static void ignoresTheSameEmailOnOtherKindsOfAccounts() {
        useTestSetup();
        Id customerType = otherAccountTypeId();
        System.assertNotEquals(null, customerType, 'The org has a second Account record type (Customer) to compare with');
        insert new Account(Name = 'Harbour Realty (customer)', Email__c = 'customer@registration-test.example.com',
            Onboarding_Status__c = PENDING, RecordTypeId = customerType);

        Test.startTest();
        partnerPortalRegistrationController.RegistrationResult result =
            partnerPortalRegistrationController.register('Company', companyValues('customer@registration-test.example.com'),
                documents(new List<String>{ 'BR.pdf' }, 100));
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.REGISTERED, result.status, result.fieldErrors);
        System.assertEquals(partnerTypeId(),
            [SELECT RecordTypeId FROM Account WHERE Email__c = 'customer@registration-test.example.com' AND Name = 'Harbour Realty'].RecordTypeId);
    }

    @isTest
    static void refusesAnEmailThatIsAlreadyRegistered() {
        // A working partner login; a colleague on the same account without one; a rejected registration without one
        User partnerUser = PartnerPortalTestUser.create();
        partnerUser = [SELECT Email, ContactId, Contact.AccountId FROM User WHERE Id = :partnerUser.Id];
        update new Contact(Id = partnerUser.ContactId, Email = partnerUser.Email);
        insert new Contact(LastName = 'Colleague', AccountId = partnerUser.Contact.AccountId, Email = 'colleague@registration-test.example.com');
        Account rejected = new Account(Name = 'Rejected Applicant', Onboarding_Status__c = 'Rejected', RecordTypeId = partnerTypeId());
        insert rejected;
        insert new Contact(LastName = 'Fernando', AccountId = rejected.Id, Email = 'rejected@registration-test.example.com');
        useTestSetup();

        Test.startTest();
        partnerPortalRegistrationController.RegistrationResult partner =
            partnerPortalRegistrationController.register('Company', companyValues(partnerUser.Email.toUpperCase()),
                documents(new List<String>{ 'BR.pdf' }, 100));
        partnerPortalRegistrationController.RegistrationResult colleague =
            partnerPortalRegistrationController.register('Company', companyValues('colleague@registration-test.example.com'),
                documents(new List<String>{ 'BR.pdf' }, 100));
        partnerPortalRegistrationController.RegistrationResult earlier =
            partnerPortalRegistrationController.register('Company', companyValues('rejected@registration-test.example.com'),
                documents(new List<String>{ 'BR.pdf' }, 100));
        Test.stopTest();

        String contactTeam = 'This email was used for an earlier registration. Please contact the JKP CP team.';
        System.assertEquals(partnerPortalRegistrationController.INVALID, partner.status);
        System.assertEquals('This email is already registered. Please log in instead.', partner.fieldErrors.get('email'),
            'The email is a partner login');
        System.assertEquals(contactTeam, colleague.fieldErrors.get('email'),
            'The account has a login, but not for this email: logging in with it would lead back to registration');
        // A rejected registration does not keep its email: registering again makes a new registration for approval
        System.assertEquals(partnerPortalRegistrationController.REGISTERED, earlier.status, earlier.fieldErrors);
        Account again = [SELECT Id, Onboarding_Status__c FROM Account WHERE Name = 'Harbour Realty'];
        System.assertEquals(PENDING, again.Onboarding_Status__c);
        System.assertEquals('Pending', [SELECT Status FROM ProcessInstance WHERE TargetObjectId = :again.Id].Status, 'Sent for approval again');
        System.assertEquals('Rejected', [SELECT Onboarding_Status__c FROM Account WHERE Id = :rejected.Id].Onboarding_Status__c,
            'The rejected registration stays as it was');
    }

    @isTest
    static void invisibleCharactersDoNotFillARequiredField() {
        useTestSetup();
        String noBreakSpace = String.fromCharArray(new List<Integer>{ 160 });
        String zeroWidthSpace = String.fromCharArray(new List<Integer>{ 8203 });
        String byteOrderMark = String.fromCharArray(new List<Integer>{ 65279 });
        Map<String, String> values = companyValues('invisible@registration-test.example.com');
        values.put('businessName', noBreakSpace);
        values.put('contactPerson', zeroWidthSpace + ' ' + byteOrderMark);

        Test.startTest();
        partnerPortalRegistrationController.RegistrationResult result =
            partnerPortalRegistrationController.register('Company', values, documents(new List<String>{ 'BR.pdf' }, 100));
        values.put('businessName', noBreakSpace + 'Harbour Realty' + zeroWidthSpace);
        values.put('contactPerson', 'Kamal Perera');
        partnerPortalRegistrationController.RegistrationResult trimmed =
            partnerPortalRegistrationController.register('Company', values, documents(new List<String>{ 'BR.pdf' }, 100));
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.INVALID, result.status);
        System.assertEquals('This field is required.', result.fieldErrors.get('businessName'));
        System.assertEquals('This field is required.', result.fieldErrors.get('contactPerson'));
        System.assertEquals(partnerPortalRegistrationController.REGISTERED, trimmed.status, trimmed.fieldErrors);
        System.assertEquals('Harbour Realty',
            [SELECT Name FROM Account WHERE Email__c = 'invisible@registration-test.example.com'].Name,
            'Invisible characters at the ends are not saved');
    }

    // ---------- documents ----------

    @isTest
    static void uploadsEachDocumentAsAFileOnTheAccount() {
        useTestSetup();
        String limitReached;

        Test.startTest();
        System.runAs(guest()) {
            // BR.pdf travels with the registration; VAT.png follows on its own
            String ticket = partnerPortalRegistrationController.register('Company', companyValues('files@registration-test.example.com'),
                documents(new List<String>{ 'BR.pdf', 'VAT.png' }, 100)).ticket;
            partnerPortalRegistrationController.uploadDocument(ticket, 'C:\\Users\\kamal\\VAT.png', PNG_DATA);
            limitReached = uploadError(ticket, 'More.pdf', PDF_DATA);
        }
        Test.stopTest();

        Account account = [SELECT Id, OwnerId FROM Account WHERE Email__c = 'files@registration-test.example.com'];
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title, ContentDocument.FileExtension, ContentDocument.OwnerId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :account.Id
            ORDER BY ContentDocument.Title
        ];
        System.assertEquals(2, links.size());
        System.assertEquals('BR', links[0].ContentDocument.Title);
        System.assertEquals('pdf', links[0].ContentDocument.FileExtension);
        System.assertEquals('VAT', links[1].ContentDocument.Title, 'Only the file name is kept, without its folders');
        System.assertEquals('png', links[1].ContentDocument.FileExtension);
        System.assertEquals(account.OwnerId, links[0].ContentDocument.OwnerId, 'Files belong to the registration owner, not the guest user');
        System.assertEquals(account.OwnerId, links[1].ContentDocument.OwnerId);
        System.assert(limitReached.contains('2 documents'), limitReached);
    }

    @isTest
    static void keepsOnlyTheFileNameEvenBehindALineBreak() {
        useTestSetup();
        Test.startTest();
        String ticket = partnerPortalRegistrationController.register('Company', companyValues('names@registration-test.example.com'),
            documents(new List<String>{ 'BR.pdf' }, 100)).ticket;
        partnerPortalRegistrationController.uploadDocument(ticket, 'x\n/../../evil.pdf', PDF_DATA);
        Test.stopTest();

        Id accountId = [SELECT Id FROM Account WHERE Email__c = 'names@registration-test.example.com'].Id;
        Set<String> paths = new Set<String>();
        for (ContentDocumentLink link : [
            SELECT ContentDocument.LatestPublishedVersion.PathOnClient
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accountId
        ]) {
            paths.add(link.ContentDocument.LatestPublishedVersion.PathOnClient);
        }
        System.assertEquals(new Set<String>{ 'BR.pdf', 'evil.pdf' }, paths, 'No folder part survives a line break');
    }

    @isTest
    static void refusesAFileThatIsNotWhatItsNameSays() {
        useTestSetup(new Map<String, Object>{ 'Max_File_Size_MB__c' => 0.01 });
        String ticket;
        Test.startTest();
        ticket = partnerPortalRegistrationController.register('Company', companyValues('checks@registration-test.example.com'),
            documents(new List<String>{ 'BR.pdf' }, 100)).ticket;
        String renamed = uploadError(ticket, 'NIC.pdf', PNG_DATA);
        String wrongType = uploadError(ticket, 'notes.txt', EncodingUtil.base64Encode(Blob.valueOf('hello')));
        String tooLarge = uploadError(ticket, 'big.pdf', EncodingUtil.base64Encode(Blob.valueOf('%PDF-' + 'x'.repeat(20000))));
        String empty = uploadError(ticket, 'empty.pdf', '');
        Test.stopTest();

        System.assertEquals('NIC.pdf is not a valid PDF file.', renamed);
        System.assertEquals('notes.txt is not a PDF or PNG file.', wrongType);
        System.assertEquals('big.pdf is larger than 0.01 MB.', tooLarge);
        System.assert(empty.contains('could not be read'), empty);
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion WHERE Title IN ('NIC', 'notes', 'big', 'empty')]);
    }

    @isTest
    static void acceptsUploadsOnlyWithAValidTicketWhileTheRegistrationIsPending() {
        useTestSetup();
        Test.startTest();
        String ticket = partnerPortalRegistrationController.register('Company', companyValues('ticket@registration-test.example.com'),
            documents(new List<String>{ 'BR.pdf' }, 100)).ticket;
        Account account = [SELECT Id FROM Account WHERE Email__c = 'ticket@registration-test.example.com'];
        Account other = new Account(Name = 'Someone Else', Onboarding_Status__c = PENDING);
        insert other;
        List<String> parts = ticket.split('\\.');

        String noTicket = uploadError(null, 'BR.pdf', PDF_DATA);
        String forged = uploadError(other.Id + '.' + parts[1] + '.' + parts[2] + '.' + parts[3], 'BR.pdf', PDF_DATA);
        String expired = uploadError(partnerPortalRegistrationController.ticketFor(account.Id, Datetime.now().addMinutes(-1)), 'BR.pdf', PDF_DATA);
        String accepted = uploadError(ticket, 'BR.pdf', PDF_DATA);
        // Once the account leaves the registration status (approved or rejected) its ticket no longer works. The status is
        // moved in the setup rather than on the account, because approving an account starts partner user creation.
        useTestSetup(new Map<String, Object>{ 'Registration_Status__c' => 'Approved' });
        String notPending = uploadError(ticket, 'Late.pdf', PDF_DATA);
        Test.stopTest();

        String closed = 'This registration can no longer receive documents. Please contact the JKP CP team to send them.';
        System.assertEquals(closed, noTicket);
        System.assertEquals(closed, forged, 'A ticket cannot be moved to another account');
        System.assertEquals(closed, expired);
        System.assertEquals('Not refused', accepted);
        System.assertEquals(closed, notPending);
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :other.Id]);
    }

    // ---------- documents in SharePoint (the channel partner record type has Document categories) ----------

    // SharePoint as Graph answers: folders, upload sessions, uploads, items and links, remembering what it made
    private class SharePointMock implements HttpCalloutMock {
        Integer failFolders;
        Integer counter = 0;
        Map<String, String> folderNames = new Map<String, String>();
        Map<String, String> folderOf = new Map<String, String>();
        Map<String, String> itemNames = new Map<String, String>();
        Map<String, String> sessionFolder = new Map<String, String>();
        Map<String, String> sessionName = new Map<String, String>();

        public HttpResponse respond(HttpRequest req) {
            String url = req.getEndpoint();
            String rest = url.substringAfter('/items/');
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getMethod() == 'POST' && url.endsWith('/children')) {
                if (failFolders != null) {
                    res.setStatusCode(failFolders);
                    res.setBody('{"error":{"code":"serviceNotAvailable"}}');
                    return res;
                }
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
                String id = 'folder-' + (++counter);
                folderNames.put(id, (String) body.get('name'));
                res.setStatusCode(201);
                res.setBody(JSON.serialize(new Map<String, Object>{ 'id' => id, 'name' => body.get('name') }));
            } else if (req.getMethod() == 'POST' && url.endsWith(':/createUploadSession')) {
                String uploadUrl = 'https://keells.sharepoint.com/upload/' + (++counter);
                sessionFolder.put(uploadUrl, rest.substringBefore(':/'));
                sessionName.put(uploadUrl, EncodingUtil.urlDecode(rest.substringAfter(':/').substringBefore(':/createUploadSession'), 'UTF-8'));
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{ 'uploadUrl' => uploadUrl }));
            } else if (req.getMethod() == 'PUT') {
                String range = req.getHeader('Content-Range');
                Long lastByte = Long.valueOf(range.substringAfter('-').substringBefore('/'));
                Long total = Long.valueOf(range.substringAfter('/'));
                if (lastByte + 1 < total) {
                    res.setStatusCode(202);
                    res.setBody('{}');
                    return res;
                }
                String id = 'item-' + (++counter);
                folderOf.put(id, sessionFolder.get(url));
                itemNames.put(id, sessionName.get(url));
                res.setStatusCode(201);
                res.setBody(JSON.serialize(new Map<String, Object>{ 'id' => id, 'name' => sessionName.get(url) }));
            } else if (req.getMethod() == 'POST' && url.endsWith('/createLink')) {
                String id = EncodingUtil.urlDecode(rest.substringBefore('/createLink'), 'UTF-8');
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'link' => new Map<String, Object>{ 'webUrl' => 'https://keells.sharepoint.com/:b:/s/JKPConnectDataHub/' + id, 'scope' => 'anonymous' }
                }));
            } else if (req.getMethod() == 'GET' && rest.contains('/children')) {
                String folderId = rest.substringBefore('/children');
                List<Object> files = new List<Object>();
                for (String id : folderOf.keySet()) {
                    if (folderOf.get(id) == folderId) {
                        files.add(new Map<String, Object>{ 'id' => id, 'file' => new Map<String, Object>() });
                    }
                }
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{ 'value' => files }));
            } else if (req.getMethod() == 'GET') {
                String id = EncodingUtil.urlDecode(rest.substringBefore('?'), 'UTF-8');
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'id' => id,
                    'name' => itemNames.get(id),
                    'parentReference' => new Map<String, Object>{ 'id' => folderOf.get(id) }
                }));
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }

    private static SharePointMock useSharePoint() {
        SharePointMock sharePoint = new SharePointMock();
        Test.setMock(HttpCalloutMock.class, sharePoint);
        SharePointService.testDriveId = 'test-drive';
        return sharePoint;
    }

    // The Document Master of channel partner accounts, its Record Type written in other capitals than the record type
    private static void createChannelPartnerMaster() {
        Document_Master__c master = new Document_Master__c(Name = 'Account', Record_Type__c = 'Channel partner');
        insert master;
        insert new List<Document_category__c>{
            new Document_category__c(Name = 'BR, VAT Certificate', Document_Master__c = master.Id),
            new Document_category__c(Name = 'NIC, TIN and passport', Document_Master__c = master.Id)
        };
    }

    // A registration whose BR, VAT Certificate folder already exists in SharePoint, and the ticket its page holds
    private static Document__c registrationWithFolder() {
        Account account = new Account(Name = 'Harbour Realty', Onboarding_Status__c = PENDING, RecordTypeId = partnerTypeId(),
            Document_Id__c = 'folder-root');
        insert account;
        Document__c folder = new Document__c(Name = 'BR, VAT Certificate', Account__c = account.Id, Document_Id__c = 'folder-br');
        insert folder;
        return folder;
    }

    @isTest
    static void keepsTheDocumentsInSharePointWhenTheRecordTypeHasCategories() {
        useTestSetup();
        createChannelPartnerMaster();
        SharePointMock sharePoint = useSharePoint();
        partnerPortalRegistrationController.RegistrationResult result;

        Test.startTest();
        System.runAs(guest()) {
            result = partnerPortalRegistrationController.register('Company', companyValues('drive@registration-test.example.com'),
                documents(new List<String>{ 'BR.pdf', 'VAT.pdf' }, 100));
        }
        Test.stopTest();

        System.assertEquals(partnerPortalRegistrationController.REGISTERED, result.status, result.fieldErrors);
        System.assertEquals(true, result.documentsInSharePoint);
        Account account = [SELECT Id, OwnerId, Document_Id__c FROM Account WHERE Email__c = 'drive@registration-test.example.com'];
        System.assertEquals('Harbour Realty', sharePoint.folderNames.get(account.Document_Id__c), 'The account\'s folder is named after it');
        List<Document__c> documents = [
            SELECT Name, Document_Id__c, OwnerId, (SELECT Name, File_URL__c, Public_Link__c, OwnerId FROM Sub_Documents__r)
            FROM Document__c
            WHERE Account__c = :account.Id
            ORDER BY Name
        ];
        System.assertEquals(2, documents.size(), 'A Document, and a sub-folder, per category');
        System.assertEquals('BR, VAT Certificate', documents[0].Name);
        System.assertEquals('BR, VAT Certificate', sharePoint.folderNames.get(documents[0].Document_Id__c));
        System.assertEquals('NIC, TIN and passport', sharePoint.folderNames.get(documents[1].Document_Id__c));
        System.assertEquals(account.OwnerId, documents[0].OwnerId, 'Owned like the account, not by the guest user');
        System.assertEquals(1, documents[0].Sub_Documents__r.size(), 'The first document came with the registration, into the Company category');
        System.assertEquals('BR.pdf', documents[0].Sub_Documents__r[0].Name);
        System.assert(documents[0].Sub_Documents__r[0].File_URL__c.startsWith('https://keells.sharepoint.com/'));
        System.assertEquals(true, documents[0].Sub_Documents__r[0].Public_Link__c, 'An "Anyone" link');
        System.assertEquals(account.OwnerId, documents[0].Sub_Documents__r[0].OwnerId);
        System.assertEquals(0, documents[1].Sub_Documents__r.size());
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :account.Id], 'Not as Salesforce Files');
    }

    @isTest
    static void uploadsTheOtherDocumentsIntoTheRegistrationsFolder() {
        useTestSetup();
        Document__c folder = registrationWithFolder();
        String ticket = partnerPortalRegistrationController.ticketFor(folder.Account__c, folder.Id, Datetime.now().addMinutes(30));
        useSharePoint();
        String vat = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 VAT certificate'));
        Integer size = EncodingUtil.base64Decode(vat).size();

        String handle;
        Test.startTest();
        System.runAs(guest()) {
            handle = partnerPortalRegistrationController.startDocumentUpload(ticket, 'VAT.pdf', size);
            SharePointDocumentManagerController.ChunkResult chunk =
                partnerPortalRegistrationController.uploadDocumentChunk(ticket, handle, vat, 0, size);
            partnerPortalRegistrationController.finishDocumentUpload(ticket, handle, chunk.itemId);
        }
        Test.stopTest();

        System.assert(!handle.containsIgnoreCase('sharepoint') && !handle.containsIgnoreCase('upload'),
            'The page never sees SharePoint\'s upload URL: ' + handle);
        List<Sub_Document__c> files = [SELECT Name, File_URL__c, Public_Link__c, OwnerId FROM Sub_Document__c WHERE Document__c = :folder.Id];
        System.assertEquals(1, files.size());
        System.assertEquals('VAT.pdf', files[0].Name);
        System.assert(files[0].File_URL__c.startsWith('https://keells.sharepoint.com/'));
        System.assertEquals(true, files[0].Public_Link__c, 'An "Anyone" link');
        System.assertEquals(UserInfo.getUserId(), files[0].OwnerId, 'Owned like its Document');
    }

    @isTest
    static void finishingTheSameFileTwiceSavesItOnce() {
        useTestSetup();
        Document__c folder = registrationWithFolder();
        String ticket = partnerPortalRegistrationController.ticketFor(folder.Account__c, folder.Id, Datetime.now().addMinutes(30));
        String handle = partnerPortalRegistrationController.handleFor('https://keells.sharepoint.com/upload/9', folder.Id, 100, 'VAT.pdf');
        insert new Sub_Document__c(Name = 'VAT.pdf', Document__c = folder.Id, File_URL__c = 'https://keells.sharepoint.com/:b:/s/JKPConnectDataHub/item-7');
        SharePointMock sharePoint = useSharePoint();
        sharePoint.folderOf.put('item-7', 'folder-br');
        sharePoint.itemNames.put('item-7', 'VAT.pdf');

        Test.startTest();
        partnerPortalRegistrationController.finishDocumentUpload(ticket, handle, 'item-7');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WHERE Document__c = :folder.Id],
            'A retry after a dropped connection does not save the file again');
    }

    @isTest
    static void refusesSharePointUploadsThatBreakTheRules() {
        useTestSetup();
        Document__c folder = registrationWithFolder();
        Document__c otherFolder = new Document__c(Name = 'NIC, TIN and passport', Account__c = folder.Account__c, Document_Id__c = 'folder-nic');
        insert otherFolder;
        String ticket = partnerPortalRegistrationController.ticketFor(folder.Account__c, folder.Id, Datetime.now().addMinutes(30));
        String filesTicket = partnerPortalRegistrationController.ticketFor(folder.Account__c, Datetime.now().addMinutes(30));
        String expired = partnerPortalRegistrationController.ticketFor(folder.Account__c, folder.Id, Datetime.now().addMinutes(-1));
        Integer pdfSize = EncodingUtil.base64Decode(PDF_DATA).size();
        Integer pngSize = EncodingUtil.base64Decode(PNG_DATA).size();
        String uploadUrl = 'https://keells.sharepoint.com/upload/1';
        String pdfHandle = partnerPortalRegistrationController.handleFor(uploadUrl, folder.Id, pdfSize, 'BR.pdf');
        String nicHandle = partnerPortalRegistrationController.handleFor(uploadUrl, folder.Id, pngSize, 'NIC.pdf');
        String otherHandle = partnerPortalRegistrationController.handleFor(uploadUrl, otherFolder.Id, pdfSize, 'BR.pdf');
        SharePointMock sharePoint = useSharePoint();
        // The folder already holds the most files allowed (2), finished or not
        sharePoint.folderOf.put('item-a', 'folder-br');
        sharePoint.folderOf.put('item-b', 'folder-br');

        Test.startTest();
        String tooLarge = startError(ticket, 'big.pdf', 2 * 1024 * 1024);
        String wrongType = startError(ticket, 'notes.docx', 100);
        String empty = startError(ticket, 'empty.pdf', 0);
        String filesMode = startError(filesTicket, 'BR.pdf', 100);
        String late = startError(expired, 'BR.pdf', 100);
        String renamed = chunkError(ticket, nicHandle, PNG_DATA, 0, pngSize);
        String tampered = chunkError(ticket, pdfHandle.left(pdfHandle.length() - 3) + 'abc', PDF_DATA, 0, pdfSize);
        String otherDocument = chunkError(ticket, otherHandle, PDF_DATA, 0, pdfSize);
        String wrongRange = chunkError(ticket, pdfHandle, PDF_DATA, 0, pdfSize + 5);
        String filesUpload = uploadError(ticket, 'BR.pdf', PDF_DATA);
        String tooMany = startError(ticket, 'c.pdf', 100);
        String fullOnLastChunk = chunkError(ticket, pdfHandle, PDF_DATA, 0, pdfSize);
        Test.stopTest();

        String closed = 'This registration can no longer receive documents. Please contact the JKP CP team to send them.';
        String invalid = 'This upload is no longer valid. Please choose the document again.';
        System.assertEquals('big.pdf is larger than 1 MB.', tooLarge);
        System.assertEquals('notes.docx is not a PDF or PNG file.', wrongType);
        System.assertEquals('empty.pdf is empty.', empty);
        System.assertEquals(closed, filesMode, 'A ticket for Salesforce Files cannot upload to SharePoint');
        System.assertEquals(closed, late);
        System.assertEquals('NIC.pdf is not a valid PDF file.', renamed);
        System.assertEquals(invalid, tampered, 'A handle cannot be altered');
        System.assertEquals(invalid, otherDocument, 'A handle only uploads into its own Document');
        System.assertEquals('BR.pdf could not be sent. Please choose it again.', wrongRange, 'A chunk must match the size accepted at the start');
        System.assertEquals(closed, filesUpload, 'A SharePoint registration does not take Salesforce Files');
        System.assert(tooMany.contains('2 documents'), tooMany);
        System.assert(fullOnLastChunk.contains('2 documents'), 'Finishing a file is refused once the folder is full: ' + fullOnLastChunk);
    }

    @isTest
    static void savesNothingWhenSharePointFails() {
        useTestSetup();
        createChannelPartnerMaster();
        SharePointMock sharePoint = useSharePoint();
        sharePoint.failFolders = 503;

        Test.startTest();
        String error = registerError('Company', companyValues('outage@registration-test.example.com'));
        Test.stopTest();

        System.assertEquals('Your documents could not be stored right now. Please try again in a few minutes.', error);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Email__c = 'outage@registration-test.example.com']);
    }

    @isTest
    static void aDocumentsInputNeedsACategoryOfTheMaster() {
        useTestSetup();
        createChannelPartnerMaster();
        useSharePoint();
        List<Partner_Registration_Field__mdt> rows = partnerPortalRegistrationController.fieldRecords;

        Test.startTest();
        rows[5] = documentsField('Company_Documents', 'Company', true, null);
        String missing = registerError('Company', companyValues('nocategory@registration-test.example.com'));
        rows[5] = documentsField('Company_Documents', 'Company', true, 'Trade Licence');
        String unknown = registerError('Company', companyValues('unknown@registration-test.example.com'));
        Test.stopTest();

        System.assert(missing.contains('Document Category'), missing);
        System.assert(unknown.contains('Trade Licence'), unknown);
    }

    private static String startError(String ticket, String fileName, Long size) {
        try {
            partnerPortalRegistrationController.startDocumentUpload(ticket, fileName, size);
            return 'Not refused';
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    private static String chunkError(String ticket, String handle, String base64Chunk, Integer startByte, Integer endByte) {
        try {
            partnerPortalRegistrationController.uploadDocumentChunk(ticket, handle, base64Chunk, startByte, endByte);
            return 'Not refused';
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    // ---------- the org's own registration setup ----------

    // Registers each type of the org's form as the site guest user, with values that suit each field, and uploads a
    // document: the deployed custom metadata must make a working form
    @isTest
    static void theOrgsRegistrationSetupWorks() {
        insert TestRecordDefaults.project('Setup Check Tower', true);
        User siteGuest = guest();
        Site site = [SELECT GuestRecordDefaultOwnerId FROM Site WHERE GuestUserId = :siteGuest.Id AND GuestRecordDefaultOwnerId != null LIMIT 1];
        Partner_Registration_Setting__mdt setting = Partner_Registration_Setting__mdt.getInstance(partnerPortalRegistrationController.SETTINGS_RECORD);
        Map<String, String> outcomes = new Map<String, String>();

        Test.startTest();
        System.runAs(siteGuest) {
            partnerPortalRegistrationController.RegistrationForm form = partnerPortalRegistrationController.getRegistrationForm();
            System.assert(!form.types.isEmpty(), 'The form has registration types');
            String extension = form.fileTypes.isEmpty() ? 'pdf' : form.fileTypes[0];
            for (partnerPortalRegistrationController.RegistrationType type : form.types) {
                Map<String, String> values = new Map<String, String>();
                for (partnerPortalRegistrationController.FormField field : type.fields) {
                    if (field.type == 'project') {
                        values.put(field.name, field.options[0].value);
                    } else if (field.type == 'email') {
                        values.put(field.name, type.value.deleteWhitespace().toLowerCase() + '@setup-check.example.com');
                    } else if (field.type == 'tel') {
                        values.put(field.name, '+94 77 123 4567');
                    } else if (field.type != 'upload') {
                        String value = 'Setup Check ' + field.name;
                        values.put(field.name, field.maxLength == null ? value : value.left(field.maxLength));
                    }
                }
                partnerPortalRegistrationController.RegistrationResult result = partnerPortalRegistrationController.register(
                    type.value, values, documents(new List<String>{ 'Document.' + extension }, 100));
                outcomes.put(type.value, result.status + ' ' + result.fieldErrors);
                if (result.ticket != null && extension == 'pdf') {
                    partnerPortalRegistrationController.uploadDocument(result.ticket, 'Document.pdf', PDF_DATA);
                }
            }
        }
        Test.stopTest();

        for (String type : outcomes.keySet()) {
            System.assert(outcomes.get(type).startsWith(partnerPortalRegistrationController.REGISTERED), type + ': ' + outcomes.get(type));
        }
        for (Account account : [
            SELECT OwnerId, RecordType.DeveloperName, Onboarding_Status__c, (SELECT Id FROM Contacts), (SELECT Id FROM ContentDocumentLinks)
            FROM Account
            WHERE CreatedById = :siteGuest.Id
        ]) {
            System.assert(!account.ContentDocumentLinks.isEmpty(), 'Each registration has its first document');
            System.assertEquals(String.isBlank(setting.Record_Owner__c) ? site.GuestRecordDefaultOwnerId : account.OwnerId, account.OwnerId,
                'Owned by the site\'s default owner for guest records');
            System.assertEquals(partnerPortalRegistrationController.registrationStatus(), account.Onboarding_Status__c);
            System.assertEquals(setting.Account_Record_Type__c, account.RecordType.DeveloperName, 'A channel partner account');
            System.assertEquals(1, account.Contacts.size());
        }
        System.assertEquals(outcomes.size(), [SELECT COUNT() FROM Account WHERE CreatedById = :siteGuest.Id]);
    }
}