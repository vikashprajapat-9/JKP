// The Documents popup of the Partner Portal Leads page (partnerWebPortalLeadDocuments), run as a partner: choosing the
// customer type, starting an upload (lead and document folders in OneDrive), sending the chunks and finishing it, and
// what is refused.
@isTest
private class partnerWebPortalLeadDocumentsTest {

    private static final String UPLOAD_URL = 'https://utillabs-my.sharepoint.com/upload/test';

    // OneDrive: folders, upload sessions, the upload, the item and its link
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
                String folder = url.substringAfter('/drive/items/').substringBefore(':/');
                String uploadUrl = 'https://utillabs-my.sharepoint.com/upload/' + sequence;
                folderByUpload.put(uploadUrl, folder);
                res.setStatusCode(200);
                res.setBody('{"uploadUrl":"' + uploadUrl + '"}');
            } else if (req.getMethod() == 'PUT') {
                String item = 'ITEM-' + sequence;
                folderByItem.put(item, folderByUpload.get(url));
                nameByItem.put(item, 'nic.pdf');
                res.setStatusCode(201);
                res.setBody('{"id":"' + item + '"}');
            } else if (url.endsWith('/createLink')) {
                res.setStatusCode(201);
                res.setBody('{"link":{"webUrl":"https://utillabs-my.sharepoint.com/:b:/g/link-' + sequence + '","scope":"anonymous"}}');
            } else if (req.getMethod() == 'GET' && url.contains('/drive/items/')) {
                String item = EncodingUtil.urlDecode(url.substringAfter('/drive/items/').substringBefore('?'), 'UTF-8');
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
    }

    private static Integer leadCount = 0;

    // The document lists of the two customer types, and the settings that name them
    private static void useDocumentLists() {
        Document_Master__c individual = new Document_Master__c(Name = 'Test Lead Individual');
        Document_Master__c company = new Document_Master__c(Name = 'Test Lead Company');
        insert new List<Document_Master__c>{ individual, company };
        insert new List<Document_category__c>{
            new Document_category__c(Name = 'NIC / Passport', Document_Master__c = individual.Id),
            new Document_category__c(Name = 'Proof of Address', Document_Master__c = individual.Id),
            new Document_category__c(Name = 'Business Registration', Document_Master__c = company.Id)
        };
        partnerWebPortalLeadDocuments.setting = new Partner_Portal_Setting__mdt(Lead_Individual_Document_Master__c = 'Test Lead Individual',
            Lead_Company_Document_Master__c = 'Test Lead Company', Lead_Document_Max_MB__c = 10,
            CP_Lead_Lost_Status__c = 'Site Visit Done by Other Agent');
    }

    private static Id accountOf(User portalUser) {
        return [SELECT Contact.AccountId FROM User WHERE Id = :portalUser.Id].Contact.AccountId;
    }

    private static Lead leadOf(Id channelPartnerId, Id ownerId, String customerType) {
        leadCount++;
        Project__c project = TestRecordDefaults.project('Lead Documents Project ' + leadCount, true);
        insert project;
        Lead record = new Lead(LastName = 'Docs Buyer ' + leadCount, Company = 'Docs Holdings ' + leadCount,
            Phone = '07712355' + String.valueOf(leadCount).leftPad(2, '0'), Email = 'docs.buyer' + leadCount + '@example.com',
            LeadSource = 'Channel Partner', Budget_Aligned__c = 'Matching Budget', Project__c = project.Id,
            Channel_Partner__c = channelPartnerId, OwnerId = ownerId, Customer_Type__c = customerType);
        insert record;
        return record;
    }

    // The type decides the documents to collect: none before it is chosen, then the type's document list
    @isTest
    static void theCustomerTypeDecidesTheDocuments() {
        useDocumentLists();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, null);

        partnerWebPortalLeadDocuments.LeadDocuments first;
        partnerWebPortalLeadDocuments.LeadDocuments individual;
        partnerWebPortalLeadDocuments.LeadDocuments company;
        Test.startTest();
        System.runAs(partner) {
            first = partnerWebPortalLeadDocuments.getLeadDocuments(record.Id);
            individual = partnerWebPortalLeadDocuments.setCustomerType(record.Id, 'Individual');
            company = partnerWebPortalLeadDocuments.setCustomerType(record.Id, 'Company');
        }
        Test.stopTest();

        System.assert(first.canUpload, first.readOnlyReason);
        System.assertEquals(null, first.customerType);
        System.assertEquals(Label.Partner_Lead_Docs_Choose_Type, first.notice);
        System.assertEquals(0, first.categories.size());
        System.assertEquals(2, first.typeOptions.size());
        System.assertEquals(2, individual.categories.size());
        System.assertEquals('NIC / Passport', individual.categories[0].name);
        System.assertEquals('Proof of Address', individual.categories[1].name);
        System.assertEquals(1, company.categories.size());
        System.assertEquals('Business Registration', company.categories[0].name);
        System.assertEquals('Company', [SELECT Customer_Type__c FROM Lead WHERE Id = :record.Id].Customer_Type__c);
    }

    // Starting an upload makes the lead's folder (inside the partner account's folder) and the document's folder
    @isTest
    static void startingAnUploadMakesTheFolders() {
        useDocumentLists();
        User partner = PartnerPortalTestUser.create();
        Id accountId = accountOf(partner);
        update new Account(Id = accountId, Document_Id__c = 'PARTNER-FOLDER');
        Lead record = leadOf(accountId, partner.Id, 'Individual');
        GraphMock mock = new GraphMock();
        OneDriveDocumentManagerController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, mock);

        String handle;
        Test.startTest();
        System.runAs(partner) {
            handle = partnerWebPortalLeadDocuments.startUpload(record.Id, 'nic / passport', 'nic.pdf', 1000);
        }
        Test.stopTest();

        System.assert(String.isNotBlank(handle));
        System.assert(mock.calls[0].contains('/drive/items/PARTNER-FOLDER/children'), 'The lead folder is inside the partner account\'s folder: ' + mock.calls);
        Lead saved = [SELECT Document_Id__c FROM Lead WHERE Id = :record.Id];
        System.assertEquals('FOLDER-1', saved.Document_Id__c);
        Document__c document = [SELECT Name, Lead__c, Document_Id__c, Status__c FROM Document__c WHERE Lead__c = :record.Id];
        System.assertEquals('NIC / Passport', document.Name);
        System.assertEquals('FOLDER-2', document.Document_Id__c);
        System.assertEquals('Pending', document.Status__c);
    }

    // The chunks go to OneDrive through Apex; finishing saves the file with its link, and the type is then fixed
    @isTest
    static void uploadingAFileSavesIt() {
        useDocumentLists();
        User partner = PartnerPortalTestUser.create();
        Lead record = leadOf(accountOf(partner), partner.Id, 'Individual');
        update new Lead(Id = record.Id, Document_Id__c = 'LEAD-FOLDER');
        Document__c document = new Document__c(Name = 'NIC / Passport', Lead__c = record.Id, Document_Id__c = 'DOC-FOLDER', Status__c = 'Pending');
        insert document;
        partnerWebPortalLeadDocuments.UploadSession session = new partnerWebPortalLeadDocuments.UploadSession();
        session.u = UPLOAD_URL;
        session.d = document.Id;
        session.l = record.Id;
        session.s = 8;
        session.n = 'nic.pdf';
        String handle = partnerWebPortalLeadDocuments.handleFor(session);
        GraphMock mock = new GraphMock();
        mock.folderByUpload.put(UPLOAD_URL, 'DOC-FOLDER');
        OneDriveDocumentManagerController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, mock);

        OneDriveDocumentManagerController.ChunkResult chunk;
        partnerWebPortalLeadDocuments.LeadDocuments result;
        String typeChange;
        Test.startTest();
        System.runAs(partner) {
            chunk = partnerWebPortalLeadDocuments.uploadChunk(record.Id, handle, EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4')), 0, 8);
            result = partnerWebPortalLeadDocuments.finishUpload(record.Id, handle, chunk.itemId);
            try {
                partnerWebPortalLeadDocuments.setCustomerType(record.Id, 'Company');
            } catch (AuraHandledException e) {
                typeChange = e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(true, chunk.complete);
        System.assertEquals(1, result.categories[0].files.size());
        System.assertEquals('nic.pdf', result.categories[0].files[0].name);
        System.assert(result.categories[0].files[0].url.startsWith('https://utillabs-my.sharepoint.com/'));
        System.assertEquals(true, result.typeLocked);
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WHERE Document__c = :document.Id]);
        System.assertEquals('Uploaded', [SELECT Status__c FROM Document__c WHERE Id = :document.Id].Status__c);
        System.assertEquals(String.format(Label.Partner_Lead_Docs_Type_Locked, new List<Object>{ 'Individual' }), typeChange);
    }

    // Wrong files, sizes, documents, handles and leads are refused before anything reaches OneDrive
    @isTest
    static void refusesWhatIsNotAllowed() {
        useDocumentLists();
        User partner = PartnerPortalTestUser.create();
        Id accountId = accountOf(partner);
        Lead noType = leadOf(accountId, partner.Id, null);
        Lead record = leadOf(accountId, partner.Id, 'Individual');
        Account executiveAccount = new Account(Name = 'Docs Executive', RecordTypeId = partnerPortalRegistrationController.partnerRecordTypeId(),
            Channel_Head__c = accountId);
        insert executiveAccount;
        Lead executives = leadOf(executiveAccount.Id, UserInfo.getUserId(), 'Individual');
        Document__c document = new Document__c(Name = 'NIC / Passport', Lead__c = record.Id, Document_Id__c = 'DOC-FOLDER');
        insert document;
        partnerWebPortalLeadDocuments.UploadSession session = new partnerWebPortalLeadDocuments.UploadSession();
        session.u = UPLOAD_URL;
        session.d = document.Id;
        session.l = record.Id;
        session.s = 8;
        session.n = 'nic.pdf';
        String handle = partnerWebPortalLeadDocuments.handleFor(session);
        String accepted = String.format(Label.Partner_Lead_Docs_Hint, new List<Object>{ '10' });

        Map<String, String> refusals = new Map<String, String>();
        partnerWebPortalLeadDocuments.LeadDocuments executiveView;
        Test.startTest();
        System.runAs(partner) {
            refusals.put('no type', startError(noType.Id, 'NIC / Passport', 'nic.pdf', 1000));
            refusals.put('wrong type of file', startError(record.Id, 'NIC / Passport', 'setup.exe', 1000));
            refusals.put('too large', startError(record.Id, 'NIC / Passport', 'nic.pdf', 11 * 1024 * 1024));
            refusals.put('unknown document', startError(record.Id, 'Payslip', 'nic.pdf', 1000));
            refusals.put('executive\'s lead', startError(executives.Id, 'NIC / Passport', 'nic.pdf', 1000));
            refusals.put('not a pdf', chunkError(record.Id, handle, EncodingUtil.base64Encode(Blob.valueOf('hello!!!'))));
            refusals.put('tampered handle', chunkError(record.Id, handle + 'x', EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4'))));
            refusals.put('another lead', chunkError(noType.Id, handle, EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4'))));
            executiveView = partnerWebPortalLeadDocuments.getLeadDocuments(executives.Id);
            try {
                partnerWebPortalLeadDocuments.setCustomerType(record.Id, 'Partnership');
            } catch (AuraHandledException e) {
                refusals.put('unknown type', e.getMessage());
            }
        }
        Test.stopTest();

        System.assertEquals(Label.Partner_Lead_Docs_Choose_Type, refusals.get('no type'));
        System.assertEquals(accepted, refusals.get('wrong type of file'));
        System.assertEquals(String.format(Label.Partner_Lead_Docs_Too_Large, new List<Object>{ 'nic.pdf', '10' }), refusals.get('too large'));
        System.assertEquals(String.format(Label.Partner_Lead_Docs_No_Categories, new List<Object>{ 'Individual' }), refusals.get('unknown document'));
        System.assertEquals(Label.Partner_Lead_Read_Only_Team, refusals.get('executive\'s lead'));
        System.assertEquals(String.format(Label.Partner_Lead_Docs_Wrong_File, new List<Object>{ 'nic.pdf', 'PDF' }), refusals.get('not a pdf'));
        System.assertEquals(Label.Partner_Lead_Docs_Upload_Expired, refusals.get('tampered handle'));
        System.assertEquals(Label.Partner_Lead_Docs_Upload_Expired, refusals.get('another lead'));
        System.assertEquals(Label.Partner_Lead_Docs_Choose_Type, refusals.get('unknown type'));
        System.assertEquals(false, executiveView.canUpload, 'A channel head sees an executive\'s documents read-only');
        System.assertEquals(Label.Partner_Lead_Read_Only_Team, executiveView.readOnlyReason);
        System.assertEquals(0, [SELECT COUNT() FROM Document__c WHERE Lead__c IN (:noType.Id, :executives.Id)]);
    }

    private static String startError(Id leadId, String category, String fileName, Long size) {
        try {
            partnerWebPortalLeadDocuments.startUpload(leadId, category, fileName, size);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }

    private static String chunkError(Id leadId, String handle, String base64Chunk) {
        try {
            partnerWebPortalLeadDocuments.uploadChunk(leadId, handle, base64Chunk, 0, 8);
            return null;
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
    }
}