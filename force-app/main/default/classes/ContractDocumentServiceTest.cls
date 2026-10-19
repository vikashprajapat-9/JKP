// The SharePoint documents of contracts (ContractDocumentService with ContractTrigger): a new contract's Documents, one
// per category of the Contract Document Master, their folders inside the account's folder (made first when the account
// has none), the generated draft PDF uploaded to the draft folder as a Sub Document instead of Salesforce Files, and a
// draft or signed copy still in Salesforce Files moved to SharePoint. SharePoint (Microsoft Graph) is a mock.
@isTest
private class ContractDocumentServiceTest {

    private static final String ACCOUNT_FOLDER = 'ACCOUNT-FOLDER';
    // Upload sessions and file links are on the SharePoint host
    private static final String SHAREPOINT = 'https://' + SharePointService.host();

    // Answers Microsoft Graph as the SharePoint library would: folders, upload sessions, uploads, the uploaded item and
    // its view link. It remembers the folder each upload went to, and every call.
    private class GraphMock implements HttpCalloutMock {
        final List<String> calls = new List<String>();
        final Map<String, String> folderByUpload = new Map<String, String>();
        final Map<String, String> folderByItem = new Map<String, String>();
        final Map<String, String> nameByItem = new Map<String, String>();
        Integer sequence = 0;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = req.getEndpoint();
            calls.add(req.getMethod() + ' ' + url);
            sequence++;
            if (req.getMethod() == 'POST' && url.endsWith('/children')) {
                res.setStatusCode(201);
                res.setBody('{"id":"FOLDER-' + sequence + '"}');
            } else if (url.endsWith(':/createUploadSession')) {
                String folder = url.substringAfter('/items/').substringBefore(':/');
                String uploadUrl = SHAREPOINT + '/upload/' + sequence;
                folderByUpload.put(uploadUrl, folder);
                nameByItem.put(uploadUrl, EncodingUtil.urlDecode(url.substringAfter('/items/').substringAfter(':/').substringBefore(':/'), 'UTF-8'));
                res.setStatusCode(200);
                res.setBody('{"uploadUrl":"' + uploadUrl + '"}');
            } else if (req.getMethod() == 'PUT') {
                String item = 'ITEM-' + sequence;
                folderByItem.put(item, folderByUpload.get(url));
                nameByItem.put(item, nameByItem.get(url));
                res.setStatusCode(201);
                res.setBody('{"id":"' + item + '"}');
            } else if (url.endsWith('/createLink')) {
                res.setStatusCode(201);
                res.setBody('{"link":{"webUrl":"' + SHAREPOINT + '/:b:/s/JKPConnectDataHub/link-' + sequence + '","scope":"anonymous"}}');
            } else if (req.getMethod() == 'GET' && url.contains('/items/')) {
                String item = EncodingUtil.urlDecode(url.substringAfter('/items/').substringBefore('?'), 'UTF-8');
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'id' => item, 'name' => nameByItem.get(item), 'parentReference' => new Map<String, Object>{ 'id' => folderByItem.get(item) }
                }));
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":{"code":"itemNotFound"}}');
            }
            return res;
        }

        Integer count(String method, String urlPart) {
            Integer found = 0;
            for (String call : calls) {
                if (call.startsWith(method + ' ') && call.contains(urlPart)) {
                    found++;
                }
            }
            return found;
        }
    }

    // The Contract Document Master with its two categories, and the settings that name them
    private static void useContractMaster() {
        Document_Master__c master = new Document_Master__c(Name = 'Contract');
        insert master;
        insert new List<Document_category__c>{
            new Document_category__c(Name = 'Contract Generated Document', Document_Master__c = master.Id),
            new Document_category__c(Name = 'Signed Document', Document_Master__c = master.Id)
        };
        ContractDocumentService.setting = new Partner_Portal_Setting__mdt(Contract_Document_Master__c = 'Contract',
            Contract_Draft_Category__c = 'Contract Generated Document', Contract_Signed_Category__c = 'Signed Document');
    }

    private static GraphMock mockGraph() {
        GraphMock mock = new GraphMock();
        SharePointService.testDriveId = 'test-drive';
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    // A customer account (no Document Master of its own, so no account folder job), with or without its SharePoint folder
    private static Account accountWithFolder(String folderId) {
        Account customer = new Account(Name = 'Contract Docs Holdings', Document_Id__c = folderId);
        insert customer;
        return customer;
    }

    private static Map<String, Document__c> documentsOf(Id contractId) {
        Map<String, Document__c> byName = new Map<String, Document__c>();
        for (Document__c doc : [SELECT Id, Name, Document_Id__c, OwnerId FROM Document__c WHERE Contract__c = :contractId]) {
            byName.put(doc.Name, doc);
        }
        return byName;
    }

    // A new contract gets one Document per category, owned like the contract, each a folder inside the account's folder
    @isTest
    static void aNewContractGetsItsDocumentFoldersInsideTheAccountFolder() {
        useContractMaster();
        GraphMock graph = mockGraph();
        Account customer = accountWithFolder(ACCOUNT_FOLDER);

        Test.startTest();
        Contract record = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today(), ContractTerm = 12);
        insert record;
        Map<String, Document__c> created = documentsOf(record.Id);
        Test.stopTest();

        System.assertEquals(new Set<String>{ 'Contract Generated Document', 'Signed Document' }, created.keySet());
        Map<String, Document__c> after = documentsOf(record.Id);
        for (Document__c doc : after.values()) {
            System.assert(doc.Document_Id__c != null && doc.Document_Id__c.startsWith('FOLDER-'), doc.Name + ' has its folder');
            System.assertEquals(UserInfo.getUserId(), doc.OwnerId, 'Owned like the contract');
        }
        System.assertEquals(2, graph.count('POST', '/items/' + ACCOUNT_FOLDER + '/children'), 'Inside the account folder');
        System.assertEquals(0, graph.count('POST', '/root/children'), 'No new top folder');
        System.assertEquals(0, [SELECT COUNT() FROM Sub_Document__c], 'Not an agent contract: no draft to upload');
    }

    // An agent contract's draft PDF goes to the draft folder in SharePoint as a Sub Document, and the contract names it; it
    // is not kept in Salesforce Files
    @isTest
    static void anAgentContractsDraftGoesToSharePointNotFiles() {
        useContractMaster();
        GraphMock graph = mockGraph();
        Account partner = new Account(Name = 'M/s Draft Holdings', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = ACCOUNT_FOLDER, Partner_Type__c = 'Temporary');
        insert partner;
        insert new Contact(AccountId = partner.Id, FirstName = 'Kamal', LastName = 'Perera', Email = 'kamal@contract-docs.example.com');
        PartnerContractService.setting = new Partner_Portal_Setting__mdt(Contract_Template__c = 'Partner_Agent_Contract', Contract_Term_Months__c = 12);

        Test.startTest();
        Contract draft = PartnerContractService.createDrafts(new List<Account>{ partner })[0];
        Test.stopTest();

        Contract saved = [SELECT Draft_Document_Id__c, Draft_Version__c FROM Contract WHERE Id = :draft.Id];
        Map<String, Document__c> documents = documentsOf(draft.Id);
        Sub_Document__c pdf = [SELECT Id, Name, Document__c, File_URL__c, Public_Link__c FROM Sub_Document__c];
        System.assertEquals(documents.get('Contract Generated Document').Id, pdf.Document__c, 'In the Contract Generated Document folder');
        System.assertEquals(pdf.Id, saved.Draft_Document_Id__c, 'The contract names its draft');
        System.assert(pdf.Name.endsWith('Draft 1.pdf'), pdf.Name);
        System.assert(pdf.File_URL__c.startsWith(SHAREPOINT + '/'), pdf.File_URL__c);
        System.assert(pdf.Public_Link__c, 'An "Anyone" link opens without a Microsoft sign-in');
        System.assertEquals(1, graph.count('POST', ':/createUploadSession'));
        System.assert(graph.count('POST', '/items/' + documents.get('Contract Generated Document').Document_Id__c + ':/') == 1,
            'Uploaded into the draft folder: ' + graph.calls);
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :draft.Id], 'Not in Salesforce Files');
    }

    // An account without a SharePoint folder gets its folder first, with the contract's folders inside it
    @isTest
    static void anAccountWithoutAFolderGetsOneFirst() {
        useContractMaster();
        GraphMock graph = mockGraph();
        Account customer = accountWithFolder(null);

        Test.startTest();
        Contract record = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today());
        insert record;
        Test.stopTest();

        String accountFolder = [SELECT Document_Id__c FROM Account WHERE Id = :customer.Id].Document_Id__c;
        System.assert(accountFolder != null && accountFolder.startsWith('FOLDER-'), 'The account has its folder now');
        System.assertEquals(1, graph.count('POST', '/root/children'), 'One account folder');
        System.assertEquals(2, graph.count('POST', '/items/' + accountFolder + '/children'), 'The contract folders inside it');
    }

    // A contract made before keeps its draft and signed copy in Salesforce Files: both move to their SharePoint folders,
    // and the contract names the Sub Documents; a later run has nothing left to do
    @isTest
    static void filesOfAnEarlierContractMoveToSharePoint() {
        GraphMock graph = mockGraph();
        Account customer = accountWithFolder(ACCOUNT_FOLDER);
        Contract record = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today(), Contract_Stage__c = 'Draft',
            Draft_Version__c = 1);
        insert record;
        Document__c draftFolder = new Document__c(Name = 'Contract Generated Document', Contract__c = record.Id, Document_Id__c = 'DRAFT-FOLDER');
        Document__c signedFolder = new Document__c(Name = 'Signed Document', Contract__c = record.Id, Document_Id__c = 'SIGNED-FOLDER');
        insert new List<Document__c>{ draftFolder, signedFolder };
        ContentVersion draftFile = new ContentVersion(Title = 'Agent Contract - Draft 1', PathOnClient = 'Agent Contract - Draft 1.pdf',
            VersionData = Blob.valueOf('%PDF draft'), FirstPublishLocationId = record.Id);
        ContentVersion signedFile = new ContentVersion(Title = 'Signed contract', PathOnClient = 'Signed contract.pdf',
            VersionData = Blob.valueOf('%PDF signed'), FirstPublishLocationId = record.Id);
        insert new List<ContentVersion>{ draftFile, signedFile };
        Map<Id, Id> documentByVersion = new Map<Id, Id>();
        for (ContentVersion version : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN (:draftFile.Id, :signedFile.Id)]) {
            documentByVersion.put(version.Id, version.ContentDocumentId);
        }
        update new Contract(Id = record.Id, Draft_Document_Id__c = documentByVersion.get(draftFile.Id),
            Signed_Document_Id__c = documentByVersion.get(signedFile.Id));
        ContractDocumentService.setting = new Partner_Portal_Setting__mdt(Contract_Draft_Category__c = 'Contract Generated Document',
            Contract_Signed_Category__c = 'Signed Document');
        System.assert(ContractDocumentService.pendingContractIds().contains(record.Id), 'Waiting to move its files');

        Test.startTest();
        System.enqueueJob(new ContractDocumentService.Job(new List<Id>{ record.Id }));
        Test.stopTest();

        Contract moved = [SELECT Draft_Document_Id__c, Signed_Document_Id__c FROM Contract WHERE Id = :record.Id];
        Sub_Document__c draft = [SELECT Name, Document__c FROM Sub_Document__c WHERE Id = :moved.Draft_Document_Id__c];
        Sub_Document__c signed = [SELECT Name, Document__c FROM Sub_Document__c WHERE Id = :moved.Signed_Document_Id__c];
        System.assertEquals(draftFolder.Id, draft.Document__c);
        System.assertEquals('Agent Contract - Draft 1.pdf', draft.Name);
        System.assertEquals(signedFolder.Id, signed.Document__c);
        System.assertEquals('Signed contract.pdf', signed.Name);
        System.assertEquals(1, graph.count('POST', '/items/DRAFT-FOLDER:/'));
        System.assertEquals(1, graph.count('POST', '/items/SIGNED-FOLDER:/'));
        System.assert(!ContractDocumentService.pendingContractIds().contains(record.Id), 'Nothing left to do');
    }

    // SharePoint refuses everything (an outage, an expired secret)
    private class SharePointDown implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setBody('{"error":{"code":"serviceNotAvailable"}}');
            return res;
        }
    }

    // A draft verified before its PDF is in SharePoint waits in Draft; the job that saves the PDF sends it for signature
    @isTest
    static void aVerifiedDraftIsSentOnceItsPdfIsSaved() {
        useContractMaster();
        mockGraph();
        Account partner = new Account(Name = 'Verified Draft Holdings', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Document_Id__c = ACCOUNT_FOLDER, Partner_Type__c = 'Temporary');
        insert partner;
        insert new Contact(AccountId = partner.Id, FirstName = 'Nimal', LastName = 'Silva', Email = 'nimal@contract-docs.example.com');
        PartnerContractService.setting = new Partner_Portal_Setting__mdt(Contract_Template__c = 'Partner_Agent_Contract');

        Test.startTest();
        Contract draft = PartnerContractService.createDrafts(new List<Account>{ partner })[0];
        Contract saved = [SELECT Verification_Task_Id__c FROM Contract WHERE Id = :draft.Id];
        update new Task(Id = saved.Verification_Task_Id__c, Status = 'Completed');
        String beforePdf = [SELECT Contract_Stage__c FROM Contract WHERE Id = :draft.Id].Contract_Stage__c;
        Test.stopTest();

        System.assertEquals('Draft', beforePdf, 'Verified, but its PDF is not in SharePoint yet');
        Contract sent = [SELECT Contract_Stage__c, Draft_Document_Id__c FROM Contract WHERE Id = :draft.Id];
        System.assertNotEquals(null, sent.Draft_Document_Id__c);
        System.assertEquals('Sent for Signature', sent.Contract_Stage__c, 'Sent once the PDF is saved');
    }

    // When SharePoint fails, the contract's owner gets a task saying so (once while it is open); the contract stays pending
    // for the nightly check
    @isTest
    static void aFailureIsToldToTheContractOwnerOnce() {
        useContractMaster();
        SharePointService.testDriveId = 'test-drive';
        Test.setMock(HttpCalloutMock.class, new SharePointDown());
        Account customer = accountWithFolder(ACCOUNT_FOLDER);
        Contract record = new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today());

        Test.startTest();
        insert record;
        Test.stopTest();
        ContractDocumentService.Job again = new ContractDocumentService.Job(new List<Id>{ record.Id });
        again.execute(null);

        String subject = String.format(ContractDocumentService.PARTNER_CONTRACT_DOCUMENTS_FAILED_SUBJECT,
            new List<Object>{ [SELECT ContractNumber FROM Contract WHERE Id = :record.Id].ContractNumber });
        List<Task> tasks = [SELECT OwnerId, Subject FROM Task WHERE WhatId = :record.Id];
        System.assertEquals(1, tasks.size(), 'Told once: ' + tasks);
        System.assertEquals(subject, tasks[0].Subject);
        System.assertEquals(UserInfo.getUserId(), tasks[0].OwnerId, 'The contract owner');
        System.assert(ContractDocumentService.pendingContractIds().contains(record.Id), 'Left for the nightly check');
    }

    // Without the Contract Document Master in the settings, or its categories, a contract gets no Documents
    @isTest
    static void withoutTheMasterAContractGetsNoDocuments() {
        Account customer = accountWithFolder(ACCOUNT_FOLDER);
        ContractDocumentService.setting = new Partner_Portal_Setting__mdt(Contract_Document_Master__c = 'No Such Master');
        mockGraph();

        Test.startTest();
        insert new Contract(AccountId = customer.Id, Status = 'Draft', StartDate = Date.today());
        ContractDocumentService.setting = new Partner_Portal_Setting__mdt();
        System.assertEquals(0, ContractDocumentService.createDocuments(new List<Contract>{ [SELECT Id, OwnerId FROM Contract LIMIT 1] }).size());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Document__c]);
        System.assert(!ContractDocumentService.isFilesId(null));
        System.assert(!ContractDocumentService.isFilesId('not an id'));
        System.assert(!ContractDocumentService.isFilesId(customer.Id));
    }
}