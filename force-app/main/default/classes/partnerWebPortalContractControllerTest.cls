// The My Contract page of the partner portal (partnerWebPortalContractController), run as a partner like the portal
// runs it: the channel head's contract at each stage, the files they may download (the draft once it is ready to sign,
// the signed scan once the contract is completed), and what is refused: other files, files that are gone or too large,
// other partners' contracts, executives and users without a partner account.
// Contracts are inserted at the stage a test needs: ContractTrigger reacts only to stage changes, and the updates here
// that record the files keep the stage.
@isTest
private class partnerWebPortalContractControllerTest {

    private static final String DRAFT_TITLE = 'Agent Contract - M/s Portal Test - Draft 2';
    private static final String DRAFT_PDF = '%PDF-1.4 the agent contract to sign';
    private static final String SIGNED_TITLE = 'Signed agent contract';
    private static final String SIGNED_SCAN = 'the signed and scanned agent contract';

    private static Id accountOf(User portalUser) {
        return [SELECT Contact.AccountId FROM User WHERE Id = :portalUser.Id].Contact.AccountId;
    }

    // The test partner, a channel head on temporary access from 4 October to 3 November 2026
    private static User temporaryPartner() {
        User partner = PartnerPortalTestUser.create();
        update new Account(Id = accountOf(partner), Partner_Type__c = 'Temporary',
            Temporary_Access_Start_Date__c = Date.newInstance(2026, 10, 4), Temporary_Access_End_Date__c = Date.newInstance(2026, 11, 3));
        return partner;
    }

    // Another channel partner account; one that already has its OneDrive folder, so no folder job is queued
    private static Account channelPartner(String name, Id channelHeadId) {
        Account partner = new Account(Name = name, RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Channel_Head__c = channelHeadId, Document_Id__c = 'test-folder');
        insert partner;
        return partner;
    }

    // A contract of the account at this stage, with what the stage needs (the Contract validation rules)
    private static Contract contractAt(Id accountId, String stage) {
        Contract record = new Contract(AccountId = accountId, Status = 'Draft', Contract_Stage__c = stage, Draft_Version__c = 2,
            ContractTerm = 12, StartDate = Date.newInstance(2026, 10, 5));
        if (stage == 'Not Signed') {
            record.Not_Signed_Reason__c = 'Wants a longer term';
        }
        if (stage == 'Signed' || stage == 'Completed') {
            record.Signed_On__c = Date.newInstance(2026, 10, 1);
        }
        if (stage == 'Completed') {
            record.Contract_Start__c = Date.newInstance(2026, 10, 5);
            record.Contract_End__c = Date.newInstance(2027, 10, 4);
        }
        insert record;
        return record;
    }

    // A file on the record, as JKP adds it; returns its ContentDocument Id
    private static Id fileOn(Id recordId, String title, String pathOnClient, String body) {
        ContentVersion version = new ContentVersion(Title = title, PathOnClient = pathOnClient, VersionData = Blob.valueOf(body),
            FirstPublishLocationId = recordId);
        insert version;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
    }

    // The contract with its draft PDF and its signed scan recorded in the document Ids, whatever its stage, so that the
    // stage alone decides what may be downloaded
    private static Contract withFiles(Contract record) {
        Contract change = new Contract(Id = record.Id,
            Draft_Document_Id__c = fileOn(record.Id, DRAFT_TITLE, 'agent-contract.pdf', DRAFT_PDF),
            Signed_Document_Id__c = fileOn(record.Id, SIGNED_TITLE, 'signed-contract.jpg', SIGNED_SCAN));
        update change;
        return change;
    }

    // OneDrive's answer for the file behind a Sub Document's link: its name, size and short-lived download URL
    private class DriveFileMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            // A file removed from OneDrive is not found
            String share = req.getEndpoint().substringAfter('/shares/').substringBefore('/');
            Boolean removed = share == OneDriveDocumentManagerController.shareId('https://utillabs-my.sharepoint.com/:b:/g/personal/removed');
            if (req.getEndpoint().contains('/shares/') && !removed) {
                res.setStatusCode(200);
                res.setBody('{"name":"Signed agent contract.pdf","size":2048,'
                    + '"@microsoft.graph.downloadUrl":"https://utillabs-my.sharepoint.com/download/signed"}');
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":{"code":"itemNotFound"}}');
            }
            return res;
        }
    }

    // The reason the file is refused, or null when it downloads
    private static String refusalOf(String kind) {
        try {
            partnerWebPortalContractController.getContractFile(kind);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    private static String contentOf(partnerWebPortalContractController.FileDownload file) {
        return EncodingUtil.base64Decode(file.base64).toString();
    }

    @isTest
    static void withoutAContractThePartnerSeesWhatComesNext() {
        User partner = temporaryPartner();

        partnerWebPortalContractController.ContractView view;
        String draftRefused;
        String signedRefused;
        Test.startTest();
        System.runAs(partner) {
            view = partnerWebPortalContractController.getMyContract();
            draftRefused = refusalOf('draft');
            signedRefused = refusalOf('signed');
        }
        Test.stopTest();

        System.assert(view.available, 'A channel head has their contract here');
        System.assert(!view.isExecutive);
        System.assert(!view.hasContract);
        System.assertEquals(0, view.step, 'No step yet');
        System.assertEquals(null, view.stage);
        System.assertEquals(null, view.contractNumber);
        System.assertEquals(Label.Partner_Portal_Contract_None, view.message);
        System.assertEquals('Temporary', view.partnerType);
        System.assertEquals('04 Oct 2026', view.temporaryStart);
        System.assertEquals('03 Nov 2026', view.temporaryEnd);
        System.assert(!view.canDownloadDraft && !view.canDownloadSigned);
        System.assertEquals(partnerWebPortalContractController.DRAFT_NOT_READY, draftRefused);
        System.assertEquals(partnerWebPortalContractController.SIGNED_NOT_READY, signedRefused);
    }

    // Each stage's step, message and downloads: the draft from Sent for Signature on, never while it is being prepared;
    // the signed scan only once the contract is Completed
    @isTest
    static void eachStageShowsItsStepMessageAndDownloads() {
        User partner = temporaryPartner();
        Id accountId = accountOf(partner);
        List<String> stages = new List<String>{ 'Draft', 'Not Signed', 'Sent for Signature', 'Signed', 'Completed' };

        Map<String, partnerWebPortalContractController.ContractView> views = new Map<String, partnerWebPortalContractController.ContractView>();
        Map<String, String> numbers = new Map<String, String>();
        Test.startTest();
        for (String stage : stages) {
            delete [SELECT Id FROM Contract WHERE AccountId = :accountId];
            Contract record = withFiles(contractAt(accountId, stage));
            numbers.put(stage, [SELECT ContractNumber FROM Contract WHERE Id = :record.Id].ContractNumber);
            System.runAs(partner) {
                views.put(stage, partnerWebPortalContractController.getMyContract());
            }
        }
        Test.stopTest();

        Map<String, Integer> steps = new Map<String, Integer>{
            'Draft' => 1, 'Not Signed' => 1, 'Sent for Signature' => 2, 'Signed' => 3, 'Completed' => 4
        };
        Map<String, String> messages = new Map<String, String>{
            'Draft' => Label.Partner_Portal_Contract_Preparing,
            'Not Signed' => Label.Partner_Portal_Contract_Preparing,
            'Sent for Signature' => Label.Partner_Portal_Contract_Ready,
            'Signed' => Label.Partner_Portal_Contract_Signed,
            'Completed' => Label.Partner_Portal_Contract_Completed
        };
        Set<String> draftDownloads = new Set<String>{ 'Sent for Signature', 'Signed', 'Completed' };
        for (String stage : stages) {
            partnerWebPortalContractController.ContractView view = views.get(stage);
            System.assert(view.available && view.hasContract, stage);
            System.assertEquals(stage, view.stage);
            System.assertEquals(numbers.get(stage), view.contractNumber, stage);
            System.assertEquals(steps.get(stage), view.step, stage);
            System.assertEquals(messages.get(stage), view.message, stage);
            System.assertEquals(draftDownloads.contains(stage), view.canDownloadDraft, 'The draft of a contract that is ' + stage);
            System.assertEquals(stage == 'Completed', view.canDownloadSigned, 'The signed scan of a contract that is ' + stage);
            System.assertEquals(2, view.draftVersion);
            System.assertEquals(12, view.termMonths);
            System.assertEquals('Temporary', view.partnerType);
            System.assertEquals('03 Nov 2026', view.temporaryEnd);
        }

        partnerWebPortalContractController.ContractView draft = views.get('Draft');
        System.assertEquals(null, draft.signedOn);
        System.assertEquals(null, draft.contractStart);
        System.assertEquals(null, draft.contractEnd);
        System.assertEquals('01 Oct 2026', views.get('Signed').signedOn);
        partnerWebPortalContractController.ContractView completed = views.get('Completed');
        System.assertEquals('01 Oct 2026', completed.signedOn);
        System.assertEquals('05 Oct 2026', completed.contractStart);
        System.assertEquals('04 Oct 2027', completed.contractEnd);
    }

    // A partner has one contract; should there be more, the page shows the newest
    @isTest
    static void showsTheLatestContract() {
        User partner = temporaryPartner();
        Id accountId = accountOf(partner);
        Contract older = contractAt(accountId, 'Completed');
        Contract newer = contractAt(accountId, 'Draft');
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-30));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));

        partnerWebPortalContractController.ContractView view;
        Test.startTest();
        System.runAs(partner) {
            view = partnerWebPortalContractController.getMyContract();
        }
        Test.stopTest();

        System.assertEquals([SELECT ContractNumber FROM Contract WHERE Id = :newer.Id].ContractNumber, view.contractNumber);
        System.assertEquals('Draft', view.stage);
        System.assertEquals(1, view.step);
    }

    // The draft cannot be downloaded while JKP prepares and verifies it; once it is Sent for Signature, the partner gets
    // the PDF to sign offline (but no signed copy yet)
    @isTest
    static void theDraftDownloadsOnlyOnceItIsReadyToSign() {
        User partner = temporaryPartner();
        Id accountId = accountOf(partner);
        withFiles(contractAt(accountId, 'Draft'));

        String whilePrepared;
        String signedWhileSent;
        partnerWebPortalContractController.FileDownload file;
        Test.startTest();
        System.runAs(partner) {
            whilePrepared = refusalOf('draft');
        }
        delete [SELECT Id FROM Contract WHERE AccountId = :accountId];
        withFiles(contractAt(accountId, 'Sent for Signature'));
        System.runAs(partner) {
            file = partnerWebPortalContractController.getContractFile('draft');
            signedWhileSent = refusalOf('signed');
        }
        Test.stopTest();

        System.assertEquals(partnerWebPortalContractController.DRAFT_NOT_READY, whilePrepared);
        System.assertEquals('Agent Contract - M-s Portal Test - Draft 2.pdf', file.fileName, 'The title with its extension, saved without a slash');
        System.assertEquals('application/pdf', file.mimeType);
        System.assertEquals(DRAFT_PDF, contentOf(file));
        System.assertEquals(partnerWebPortalContractController.SIGNED_NOT_READY, signedWhileSent);
    }

    // Signed: the draft still downloads, the signed scan not yet; Completed: the signed scan downloads too
    @isTest
    static void theSignedCopyDownloadsOnceTheContractIsCompleted() {
        User partner = temporaryPartner();
        Id accountId = accountOf(partner);
        withFiles(contractAt(accountId, 'Signed'));

        String signedWhileSigned;
        partnerWebPortalContractController.FileDownload draftWhileSigned;
        partnerWebPortalContractController.FileDownload signed;
        partnerWebPortalContractController.FileDownload draft;
        Test.startTest();
        System.runAs(partner) {
            signedWhileSigned = refusalOf('signed');
            draftWhileSigned = partnerWebPortalContractController.getContractFile('draft');
        }
        delete [SELECT Id FROM Contract WHERE AccountId = :accountId];
        withFiles(contractAt(accountId, 'Completed'));
        System.runAs(partner) {
            signed = partnerWebPortalContractController.getContractFile(' Signed ');
            draft = partnerWebPortalContractController.getContractFile('DRAFT');
        }
        Test.stopTest();

        System.assertEquals(partnerWebPortalContractController.SIGNED_NOT_READY, signedWhileSigned);
        System.assertEquals(DRAFT_PDF, contentOf(draftWhileSigned));
        System.assertEquals(SIGNED_TITLE + '.jpg', signed.fileName);
        System.assertEquals('image/jpeg', signed.mimeType);
        System.assertEquals(SIGNED_SCAN, contentOf(signed));
        System.assertEquals(DRAFT_PDF, contentOf(draft), 'The draft stays available');
    }

    // Kinds of file the page does not have, and files that are gone or too large to send
    @isTest
    static void refusesOtherFilesAndFilesItCannotSend() {
        User partner = temporaryPartner();
        Id accountId = accountOf(partner);
        Contract record = withFiles(contractAt(accountId, 'Sent for Signature'));
        Id goneFileId = fileOn(record.Id, 'Removed draft', 'removed-draft.pdf', DRAFT_PDF);
        delete new ContentDocument(Id = goneFileId);

        String otherKind;
        String noKind;
        String tooLarge;
        List<String> notFound = new List<String>();
        Test.startTest();
        System.runAs(partner) {
            otherKind = refusalOf('invoice');
            noKind = refusalOf(null);
            partnerWebPortalContractController.maxFileBytes = DRAFT_PDF.length() - 1;
            tooLarge = refusalOf('draft');
            partnerWebPortalContractController.maxFileBytes = 3 * 1024 * 1024;
        }
        for (String documentId : new List<String>{ String.valueOf(goneFileId), 'not-a-file-id', String.valueOf(record.Id) }) {
            update new Contract(Id = record.Id, Draft_Document_Id__c = documentId);
            System.runAs(partner) {
                notFound.add(refusalOf('draft'));
            }
        }
        Test.stopTest();

        System.assertEquals(partnerWebPortalContractController.UNKNOWN_FILE, otherKind);
        System.assertEquals(partnerWebPortalContractController.UNKNOWN_FILE, noKind);
        System.assertEquals(partnerWebPortalContractController.FILE_TOO_LARGE, tooLarge);
        for (String refusal : notFound) {
            System.assertEquals(partnerWebPortalContractController.FILE_NOT_FOUND, refusal, 'A deleted file, text that is no Id, a record that is no file');
        }
    }

    // Neither another channel partner's contract nor an executive's is the partner's
    @isTest
    static void anotherPartnersContractIsNeverShown() {
        User partner = temporaryPartner();
        Account other = channelPartner('Another Channel Partner', null);
        Account executive = channelPartner('An Executive Of The Partner', accountOf(partner));
        withFiles(contractAt(other.Id, 'Completed'));
        withFiles(contractAt(executive.Id, 'Sent for Signature'));

        partnerWebPortalContractController.ContractView view;
        String draftRefused;
        String signedRefused;
        Test.startTest();
        System.runAs(partner) {
            view = partnerWebPortalContractController.getMyContract();
            draftRefused = refusalOf('draft');
            signedRefused = refusalOf('signed');
        }
        Test.stopTest();

        System.assert(view.available);
        System.assert(!view.hasContract, 'Only the partner\'s own contract');
        System.assertEquals(0, view.step);
        System.assertEquals(null, view.contractNumber);
        System.assert(!view.canDownloadDraft && !view.canDownloadSigned);
        System.assertEquals(partnerWebPortalContractController.DRAFT_NOT_READY, draftRefused);
        System.assertEquals(partnerWebPortalContractController.SIGNED_NOT_READY, signedRefused);
    }

    // An executive's channel partner holds the contract: the executive sees only that, and downloads nothing, not even a
    // contract of their own account or their channel head's
    @isTest
    static void anExecutiveIsToldTheirChannelPartnerHoldsTheContract() {
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>());
        Id executiveAccountId = accountOf(executive);
        Id headAccountId = [SELECT Channel_Head__c FROM Account WHERE Id = :executiveAccountId].Channel_Head__c;
        withFiles(contractAt(executiveAccountId, 'Completed'));
        withFiles(contractAt(headAccountId, 'Sent for Signature'));

        partnerWebPortalContractController.ContractView view;
        String draftRefused;
        String signedRefused;
        Test.startTest();
        System.runAs(executive) {
            view = partnerWebPortalContractController.getMyContract();
            draftRefused = refusalOf('draft');
            signedRefused = refusalOf('signed');
        }
        Test.stopTest();

        System.assert(!view.available, 'No contract page for an executive');
        System.assert(view.isExecutive);
        System.assert(!view.hasContract);
        System.assertEquals(0, view.step);
        System.assertEquals(Label.Partner_Portal_Contract_Executive, view.message);
        System.assertEquals(null, view.contractNumber);
        System.assertEquals(null, view.partnerType);
        System.assert(!view.canDownloadDraft && !view.canDownloadSigned);
        System.assertEquals(Label.Partner_Portal_Contract_Executive, draftRefused);
        System.assertEquals(Label.Partner_Portal_Contract_Executive, signedRefused);
    }

    // An internal user previewing the site has no partner account, so no contract
    @isTest
    static void aUserWithoutAPartnerAccountHasNoContract() {
        partnerWebPortalContractController.ContractView view = partnerWebPortalContractController.getMyContract();

        System.assert(!view.available);
        System.assert(!view.isExecutive);
        System.assert(!view.hasContract);
        System.assertEquals(Label.Partner_Portal_Contract_None, view.message);
        System.assertEquals(partnerWebPortalContractController.NOT_A_PARTNER, refusalOf('draft'));
        System.assertEquals(partnerWebPortalContractController.NOT_A_PARTNER, refusalOf('signed'));
    }

    @isTest
    static void namesAndTypesTheSavedFile() {
        System.assertEquals('Agent Contract - M-s Zara - Draft 1.pdf', partnerWebPortalContractController.fileNameOf('Agent Contract - M/s Zara - Draft 1', 'pdf'));
        System.assertEquals('Signed contract.PDF', partnerWebPortalContractController.fileNameOf(' Signed contract.PDF ', 'pdf'), 'Not a second extension');
        System.assertEquals('a-b-c-d-e-f-g-h-i.txt', partnerWebPortalContractController.fileNameOf('a\\b/c:d*e?f"g<h>i', 'txt'));
        System.assertEquals('Contract', partnerWebPortalContractController.fileNameOf(null, null));

        System.assertEquals('application/pdf', partnerWebPortalContractController.mimeTypeOf('PDF', 'pdf'));
        System.assertEquals('image/png', partnerWebPortalContractController.mimeTypeOf('PNG', 'png'));
        System.assertEquals('image/jpeg', partnerWebPortalContractController.mimeTypeOf(null, 'jpeg'), 'By extension without a file type');
        System.assertEquals('application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            partnerWebPortalContractController.mimeTypeOf('WORD_X', 'docx'));
        System.assertEquals('application/octet-stream', partnerWebPortalContractController.mimeTypeOf('UNKNOWN', 'xyz'));
    }

    // A contract made since its files moved to OneDrive: the signed scan is a Sub Document in the contract's Signed
    // Document folder, saved from a short-lived OneDrive link (no contents travel to the page)
    @isTest
    static void aOneDriveFileIsSavedFromItsDownloadLink() {
        User partner = temporaryPartner();
        Contract record = contractAt(accountOf(partner), 'Completed');
        Document__c signedFolder = new Document__c(Name = 'Signed Document', Contract__c = record.Id, Document_Id__c = 'SIGNED-FOLDER');
        insert signedFolder;
        Sub_Document__c scan = new Sub_Document__c(Name = 'Signed agent contract.pdf', Document__c = signedFolder.Id,
            File_URL__c = 'https://utillabs-my.sharepoint.com/:b:/g/personal/signed');
        insert scan;
        update new Contract(Id = record.Id, Signed_Document_Id__c = scan.Id);
        OneDriveDocumentManagerController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new DriveFileMock());

        partnerWebPortalContractController.FileDownload file;
        Test.startTest();
        System.runAs(partner) {
            file = partnerWebPortalContractController.getContractFile('signed');
        }
        Test.stopTest();

        System.assertEquals('https://utillabs-my.sharepoint.com/download/signed', file.url);
        System.assertEquals(null, file.base64, 'No contents travel to the page');
        System.assertEquals('Signed agent contract.pdf', file.fileName);
        System.assertEquals('application/pdf', file.mimeType);
    }

    // When OneDrive cannot give the file, the partner sees the page's own message, not OneDrive's error
    @isTest
    static void aMissingOneDriveFileGivesThePagesMessage() {
        User partner = temporaryPartner();
        Contract record = contractAt(accountOf(partner), 'Completed');
        Document__c signedFolder = new Document__c(Name = 'Signed Document', Contract__c = record.Id, Document_Id__c = 'SIGNED-FOLDER');
        insert signedFolder;
        Sub_Document__c scan = new Sub_Document__c(Name = 'Signed agent contract.pdf', Document__c = signedFolder.Id,
            File_URL__c = 'https://utillabs-my.sharepoint.com/:b:/g/personal/removed');
        insert scan;
        update new Contract(Id = record.Id, Signed_Document_Id__c = scan.Id);
        OneDriveDocumentManagerController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new DriveFileMock());

        String refused;
        Test.startTest();
        System.runAs(partner) {
            refused = refusalOf('signed');
        }
        Test.stopTest();

        System.assertEquals(partnerWebPortalContractController.FILE_NOT_FOUND, refused);
    }
}