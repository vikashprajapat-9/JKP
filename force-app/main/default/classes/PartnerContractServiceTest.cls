// The exclusive agent contract of a channel partner (PartnerContractService with ContractTrigger,
// PartnerContractTaskTrigger and PartnerContractChangeTrigger): the draft and its verification by the CP Manager and the
// Head of Sales, sending it for signature, the offline signature recorded by the CP Executive (Signed: Exclusive; Not
// Signed: a new draft), and completion with the signed scan and the contract dates.
@isTest
private class PartnerContractServiceTest {

    // The account owner, whose manager is the CP Manager; the Head of Sales; the CP Executive
    private class People {
        User owner;
        User cpManager;
        User headOfSales;
        User cpExecutive;
    }

    private static People people() {
        People team = new People();
        Id adminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        // The profile of the org's own CP Executive (the user the settings name), so renaming that profile does not break the tests
        Partner_Portal_Setting__mdt orgSetting = Partner_Portal_Setting__mdt.getInstance('Default');
        List<User> orgExecutive = orgSetting == null || String.isBlank(orgSetting.CP_Executive_Username__c) ? new List<User>() :
            [SELECT ProfileId FROM User WHERE Username = :orgSetting.CP_Executive_Username__c LIMIT 1];
        Id cpExecutiveProfileId = orgExecutive.isEmpty() ? adminProfileId : orgExecutive[0].ProfileId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            team.cpManager = newUser(adminProfileId, 'ctmgr', null);
            team.headOfSales = newUser(adminProfileId, 'cthos', null);
            team.cpExecutive = newUser(cpExecutiveProfileId, 'ctexe', null);
            insert new List<User>{ team.cpManager, team.headOfSales, team.cpExecutive };
            team.owner = newUser(adminProfileId, 'ctown', team.cpManager.Id);
            insert team.owner;
        }
        PartnerContractService.setting = (Partner_Portal_Setting__mdt) JSON.deserialize(JSON.serialize(new Map<String, Object>{
            'DeveloperName' => 'Default',
            'Contract_Template__c' => 'Partner_Agent_Contract',
            'Contract_Ready_Email_Template__c' => 'Partner_Contract_Ready',
            'Contract_Term_Months__c' => 12,
            'Head_Of_Sales_Username__c' => team.headOfSales.Username,
            'CP_Executive_Username__c' => team.cpExecutive.Username,
            'Contract_Signed_Category__c' => 'Signed Document'
        }), Partner_Portal_Setting__mdt.class);
        return team;
    }

    private static User newUser(Id profileId, String alias, Id managerId) {
        return new User(
            ProfileId = profileId,
            ManagerId = managerId,
            LastName = 'Contract Test ' + alias,
            Alias = alias,
            Email = alias + '@contract-test.example.com',
            Username = alias + '.' + UserInfo.getOrganizationId() + '@contract-test.example.com',
            TimeZoneSidKey = 'Asia/Colombo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    // A channel head on temporary access, with the contact who signs
    private static Account partnerOf(People team) {
        Account partner = new Account(Name = 'Contract Test Realty', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            OwnerId = team.owner.Id, Document_Id__c = 'test-folder', Partner_Type__c = 'Temporary',
            Temporary_Access_Start_Date__c = Date.today().addDays(-20), Temporary_Access_End_Date__c = Date.today().addDays(10));
        insert partner;
        insert new Contact(AccountId = partner.Id, FirstName = 'Kamal', LastName = 'Perera', Email = 'kamal@contract-test.example.com');
        return partner;
    }

    private static Contract contractOf(Id contractId) {
        return [
            SELECT Id, AccountId, OwnerId, Status, Contract_Stage__c, Draft_Version__c, ContractTerm, CustomerSignedId, CustomerSignedDate,
                Draft_Document_Id__c, Signed_Document_Id__c, Verification_Task_Id__c, Head_Of_Sales_Task_Id__c, Signed_On__c, StartDate
            FROM Contract WHERE Id = :contractId
        ];
    }

    // The draft PDF of the contract as the SharePoint job saves it (ContractDocumentService): a Sub Document in the
    // contract's Contract Generated Document folder, named by Draft_Document_Id__c
    private static Id withDraftPdf(Id contractId) {
        Document__c folder = new Document__c(Name = 'Contract Generated Document', Contract__c = contractId, Document_Id__c = 'DRAFT-FOLDER');
        insert folder;
        Sub_Document__c pdf = new Sub_Document__c(Name = 'Agent Contract - Draft.pdf', Document__c = folder.Id, File_URL__c = 'https://example.com/draft');
        insert pdf;
        update new Contract(Id = contractId, Draft_Document_Id__c = pdf.Id);
        return pdf.Id;
    }

    // The contract drafted for the partner, its PDF saved, and verified by the CP Manager and the Head of Sales: Sent for
    // Signature
    private static Contract sentContract(People team, Account partner) {
        Contract draft = contractOf(PartnerContractService.createDrafts(new List<Account>{ partner })[0].Id);
        withDraftPdf(draft.Id);
        System.runAs(team.cpManager) {
            update new Task(Id = draft.Verification_Task_Id__c, Status = 'Completed');
        }
        System.runAs(team.headOfSales) {
            update new Task(Id = draft.Head_Of_Sales_Task_Id__c, Status = 'Completed');
        }
        return contractOf(draft.Id);
    }

    // The error that refuses the change, or null when it is saved
    private static String errorOf(Contract change, User changedBy) {
        try {
            System.runAs(changedBy) {
                update change;
            }
            return null;
        } catch (DmlException e) {
            return e.getDmlMessage(0);
        }
    }

    // A first draft: the Contract (Draft, owned by the CP Executive, signed by the partner's contact), its PDF, and the
    // verification tasks of the CP Manager and the Head of Sales; a partner gets only one contract. The contract is Sent
    // for Signature only once both have closed their task.
    @isTest
    static void draftsVerifiesAndSendsTheContractForSignature() {
        People team = people();
        Account partner = partnerOf(team);
        Id contactId = [SELECT Id FROM Contact WHERE AccountId = :partner.Id].Id;

        Test.startTest();
        List<Contract> drafts = PartnerContractService.createDrafts(new List<Account>{ partner });
        List<Contract> again = PartnerContractService.createDrafts(new List<Account>{ partner });
        Contract draft = contractOf(drafts[0].Id);
        Id pdfId = withDraftPdf(draft.Id);
        Task managerTask = [SELECT OwnerId, Status, Subject, Description FROM Task WHERE Id = :draft.Verification_Task_Id__c];
        Task headOfSalesTask = [SELECT OwnerId, Status FROM Task WHERE Id = :draft.Head_Of_Sales_Task_Id__c];
        System.runAs(team.cpManager) {
            update new Task(Id = draft.Verification_Task_Id__c, Status = 'Completed');
        }
        Contract afterManager = contractOf(draft.Id);
        String headOfSalesStatus = [SELECT Status FROM Task WHERE Id = :draft.Head_Of_Sales_Task_Id__c].Status;
        System.runAs(team.headOfSales) {
            update new Task(Id = draft.Head_Of_Sales_Task_Id__c, Status = 'Completed');
        }
        Test.stopTest();

        System.assertEquals('Draft', afterManager.Contract_Stage__c, 'Waits for the Head of Sales');
        System.assertNotEquals('Completed', headOfSalesStatus, 'Nothing is closed for the Head of Sales');
        System.assertEquals(0, again.size(), 'One contract per partner');
        System.assertEquals('Draft', draft.Contract_Stage__c);
        System.assertEquals('Draft', draft.Status);
        System.assertEquals(1, draft.Draft_Version__c);
        System.assertEquals(12, draft.ContractTerm);
        System.assertEquals(team.cpExecutive.Id, draft.OwnerId, 'The CP Executive of the settings');
        System.assertEquals(contactId, draft.CustomerSignedId, 'The partner who signs');
        System.assertEquals(null, draft.Draft_Document_Id__c, 'Its PDF goes to SharePoint (ContractDocumentService), not made here');
        System.assertEquals(pdfId, contractOf(draft.Id).Draft_Document_Id__c);
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :draft.Id], 'Not kept in Salesforce Files');
        System.assertEquals(team.cpManager.Id, managerTask.OwnerId, 'The account owner\'s manager');
        System.assert(managerTask.Subject.contains('Contract Test Realty'), managerTask.Subject);
        System.assertEquals(team.headOfSales.Id, headOfSalesTask.OwnerId);

        Contract sent = contractOf(draft.Id);
        System.assertEquals('Sent for Signature', sent.Contract_Stage__c);
        System.assertEquals('In Approval Process', sent.Status);
        System.assertEquals('Temporary', [SELECT Partner_Type__c FROM Account WHERE Id = :partner.Id].Partner_Type__c, 'Not Exclusive before signing');
    }

    // The order does not matter: the Head of Sales first, then the CP Manager
    @isTest
    static void sendsForSignatureWhicheverVerifierClosesLast() {
        People team = people();
        Account partner = partnerOf(team);
        Contract draft = contractOf(PartnerContractService.createDrafts(new List<Account>{ partner })[0].Id);
        withDraftPdf(draft.Id);

        Test.startTest();
        System.runAs(team.headOfSales) {
            update new Task(Id = draft.Head_Of_Sales_Task_Id__c, Status = 'Completed');
        }
        String afterHeadOfSales = contractOf(draft.Id).Contract_Stage__c;
        System.runAs(team.cpManager) {
            update new Task(Id = draft.Verification_Task_Id__c, Status = 'Completed');
        }
        Test.stopTest();

        System.assertEquals('Draft', afterHeadOfSales, 'Waits for the CP Manager');
        System.assertEquals('Sent for Signature', contractOf(draft.Id).Contract_Stage__c);
    }

    // Verified before its draft PDF is in SharePoint: the contract waits in Draft (the partner is not told), and goes for
    // signature as soon as the PDF is saved
    @isTest
    static void aVerifiedDraftWaitsForItsPdf() {
        People team = people();
        Account partner = partnerOf(team);
        Contract draft = contractOf(PartnerContractService.createDrafts(new List<Account>{ partner })[0].Id);

        Test.startTest();
        System.runAs(team.cpManager) {
            update new Task(Id = draft.Verification_Task_Id__c, Status = 'Completed');
        }
        System.runAs(team.headOfSales) {
            update new Task(Id = draft.Head_Of_Sales_Task_Id__c, Status = 'Completed');
        }
        String withoutPdf = contractOf(draft.Id).Contract_Stage__c;
        withDraftPdf(draft.Id);
        PartnerContractService.sendVerifiedForSignature(new Set<Id>{ draft.Id });
        Test.stopTest();

        System.assertEquals('Draft', withoutPdf, 'Not sent without its PDF');
        Contract sent = contractOf(draft.Id);
        System.assertEquals('Sent for Signature', sent.Contract_Stage__c, 'Sent once the PDF is saved');
        System.assertEquals('In Approval Process', sent.Status);
    }

    // Without a Head of Sales in the settings, the CP Manager's task alone verifies the draft
    @isTest
    static void withoutAHeadOfSalesTheCpManagerVerifiesAlone() {
        People team = people();
        PartnerContractService.setting.Head_Of_Sales_Username__c = null;
        Account partner = partnerOf(team);
        Contract draft = contractOf(PartnerContractService.createDrafts(new List<Account>{ partner })[0].Id);
        withDraftPdf(draft.Id);

        Test.startTest();
        System.runAs(team.cpManager) {
            update new Task(Id = draft.Verification_Task_Id__c, Status = 'Completed');
        }
        Test.stopTest();

        System.assertEquals(null, draft.Head_Of_Sales_Task_Id__c, 'No Head of Sales task');
        System.assertEquals('Sent for Signature', contractOf(draft.Id).Contract_Stage__c);
    }

    // Signed (with the date) makes the partner Exclusive and gives the CP Executive the upload task; Completed needs the
    // contract dates and the signed scan in the contract's Signed Document folder (not just any file of the contract),
    // which becomes the Signed Document, and activates the contract
    @isTest
    static void signedMakesThePartnerExclusiveAndCompletedActivatesTheContract() {
        People team = people();
        Account partner = partnerOf(team);
        Contract sent = sentContract(team, partner);
        Date signedOn = Date.today().addDays(-1);

        Test.startTest();
        String withoutDate = errorOf(new Contract(Id = sent.Id, Contract_Stage__c = 'Signed'), team.cpExecutive);
        System.assertEquals(null, errorOf(new Contract(Id = sent.Id, Contract_Stage__c = 'Signed', Signed_On__c = signedOn), team.cpExecutive));
        Test.getEventBus().deliver();
        String partnerType = [SELECT Partner_Type__c FROM Account WHERE Id = :partner.Id].Partner_Type__c;
        List<Task> uploadTasks = [SELECT OwnerId, Subject FROM Task WHERE WhatId = :sent.Id AND OwnerId = :team.cpExecutive.Id];
        // The draft PDF (sentContract) is in the Contract Generated Document folder: it is not a signed copy
        Document__c signedFolder = new Document__c(Name = 'Signed Document', Contract__c = sent.Id, Document_Id__c = 'SIGNED-FOLDER');
        insert signedFolder;
        String withoutScan = errorOf(new Contract(Id = sent.Id, Contract_Stage__c = 'Completed', Contract_Start__c = Date.today(),
            Contract_End__c = Date.today().addYears(1)), team.cpExecutive);
        Sub_Document__c scan = new Sub_Document__c(Name = 'Signed agent contract.pdf', Document__c = signedFolder.Id,
            File_URL__c = 'https://example.com/signed');
        insert scan;
        String withoutDates = errorOf(new Contract(Id = sent.Id, Contract_Stage__c = 'Completed'), team.cpExecutive);
        System.assertEquals(null, errorOf(new Contract(Id = sent.Id, Contract_Stage__c = 'Completed', Contract_Start__c = Date.today(),
            Contract_End__c = Date.today().addYears(1)), team.cpExecutive));
        Test.getEventBus().deliver();
        Test.stopTest();

        System.assertEquals('Enter the date the partner signed the contract.', withoutDate);
        System.assertEquals('Exclusive', partnerType, 'Master Agent confirmed to Exclusive');
        System.assertEquals(1, uploadTasks.size(), 'The CP Executive uploads the signed scan');
        System.assert(uploadTasks[0].Subject.contains('Contract Test Realty'), uploadTasks[0].Subject);
        System.assert(withoutDates.startsWith('Enter the start and end dates'), withoutDates);
        System.assertEquals(PartnerContractService.PARTNER_CONTRACT_SIGNED_COPY_NEEDED, withoutScan);
        Contract completed = contractOf(sent.Id);
        System.assertEquals('Completed', completed.Contract_Stage__c);
        System.assertEquals('Activated', completed.Status);
        System.assertEquals(signedOn, completed.CustomerSignedDate);
        System.assertEquals(Date.today(), completed.StartDate);
        System.assertEquals(scan.Id, completed.Signed_Document_Id__c, 'The scan in the Signed Document folder');
    }

    // Not Signed (with the reason): the next version of the draft goes to verification again, with the reason
    @isTest
    static void notSignedDraftsTheNextVersionForVerification() {
        People team = people();
        Account partner = partnerOf(team);
        Contract sent = sentContract(team, partner);

        Test.startTest();
        String withoutReason = errorOf(new Contract(Id = sent.Id, Contract_Stage__c = 'Not Signed'), team.cpExecutive);
        System.assertEquals(null, errorOf(new Contract(Id = sent.Id, Contract_Stage__c = 'Not Signed',
            Not_Signed_Reason__c = 'Wants a 24-month term'), team.cpExecutive));
        Test.stopTest();

        System.assertEquals('Enter why the partner did not sign the contract.', withoutReason);
        Contract redrafted = contractOf(sent.Id);
        System.assertEquals('Draft', redrafted.Contract_Stage__c);
        System.assertEquals('Draft', redrafted.Status);
        System.assertEquals(2, redrafted.Draft_Version__c);
        System.assertEquals(null, redrafted.Draft_Document_Id__c, 'The next draft\'s PDF goes to SharePoint (ContractDocumentService)');
        System.assertNotEquals(sent.Verification_Task_Id__c, redrafted.Verification_Task_Id__c, 'New verification tasks');
        Task managerTask = [SELECT OwnerId, Description, Status FROM Task WHERE Id = :redrafted.Verification_Task_Id__c];
        System.assertEquals(team.cpManager.Id, managerTask.OwnerId);
        System.assert(managerTask.Description.contains('Wants a 24-month term'), managerTask.Description);
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :sent.Id], 'Not kept in Salesforce Files');
        System.assertEquals('Temporary', [SELECT Partner_Type__c FROM Account WHERE Id = :partner.Id].Partner_Type__c);
    }

    // The CP Executive moves a contract only to the next step: not to Signed while it is still being verified, and
    // nothing back to an earlier step
    @isTest
    static void theStagesGoInOrder() {
        People team = people();
        Account partner = partnerOf(team);
        Contract draft = contractOf(PartnerContractService.createDrafts(new List<Account>{ partner })[0].Id);

        Test.startTest();
        String tooEarly = errorOf(new Contract(Id = draft.Id, Contract_Stage__c = 'Signed', Signed_On__c = Date.today()), team.cpExecutive);
        Test.stopTest();

        System.assertEquals(String.format(PartnerContractService.PARTNER_CONTRACT_STAGE_ORDER, new List<Object>{ 'Draft', 'Signed' }), tooEarly);
        System.assertEquals('Draft', contractOf(draft.Id).Contract_Stage__c);
    }

    // Without the contract template there is no draft, and the reason says which setting to fix
    @isTest
    static void aMissingContractTemplateIsReported() {
        People team = people();
        Account partner = partnerOf(team);
        PartnerContractService.setting.Contract_Template__c = 'No_Such_Contract_Template';

        String reason;
        Test.startTest();
        try {
            PartnerContractService.createDrafts(new List<Account>{ partner });
        } catch (PartnerContractService.ContractException e) {
            reason = e.getMessage();
        }
        Test.stopTest();

        System.assert(reason != null && reason.contains('No_Such_Contract_Template'), reason);
    }

    // Changes without a contract, or of another kind, change nothing
    @isTest
    static void ignoresChangesItDoesNotKnow() {
        PartnerContractService.applyChanges(new List<Partner_Contract_Change__e>{
            new Partner_Contract_Change__e(Change__c = 'Signed'),
            new Partner_Contract_Change__e(Contract_Id__c = '800000000000000AAA', Change__c = 'Other')
        });
        PartnerContractService.verificationTasksClosed(new List<Task>(), null);
        System.assertEquals(0, [SELECT COUNT() FROM Contract]);
    }
}