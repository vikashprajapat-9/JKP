@isTest
private class SharePointDocumentManagerControllerTest {

    private static final String DRIVE_ID = 'DRIVE-1';
    // The library every folder and file address starts with
    private static final String LIBRARY = 'callout:SharePoint_Graph/v1.0/drives/' + DRIVE_ID;
    private static final String FOLDER_ID = 'FOLDER-1';
    // Upload sessions and share links are on the SharePoint host in the setting
    private static final String HOST = SharePointService.host();
    private static final String UPLOAD_URL = 'https://' + HOST + '/sites/JKPConnectDataHub/_api/v2.0/drives/' + DRIVE_ID + '/items/X/uploadSession?guid=1';
    private static final String LINK_URL = 'https://' + HOST + '/:b:/s/JKPConnectDataHub/abc';

    // Answers every Microsoft Graph call the controller makes, and remembers each method and address
    private class GraphMock implements HttpCalloutMock {
        private Integer anonymousLinkStatus;
        private String itemParentId;
        public List<String> calls = new List<String>();
        public List<String> folderNames = new List<String>();
        // Upload ranges sent through the Named Credential (they belong on the pre-signed address), and Graph calls that
        // bypassed it
        public Integer rangesThroughCredential = 0;
        public Integer graphCallsOutsideCredential = 0;

        GraphMock(Integer anonymousLinkStatus, String itemParentId) {
            this.anonymousLinkStatus = anonymousLinkStatus;
            this.itemParentId = itemParentId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = req.getEndpoint();
            calls.add(req.getMethod() + ' ' + url);
            if (req.getMethod() == 'PUT') {
                rangesThroughCredential += url.startsWith('callout:') ? 1 : 0;
            } else if (!url.startsWith('callout:SharePoint_Graph/v1.0/')) {
                graphCallsOutsideCredential++;
            }
            if (url.endsWith(':/createUploadSession')) {
                res.setStatusCode(200);
                res.setBody('{"uploadUrl":"' + UPLOAD_URL + '"}');
            } else if (req.getMethod() == 'PUT') {
                Boolean lastChunk = req.getHeader('Content-Range').endsWith('-9/10');
                res.setStatusCode(lastChunk ? 201 : 202);
                res.setBody(lastChunk ? '{"id":"ITEM-1"}' : '{"nextExpectedRanges":["5-"]}');
            } else if (url.endsWith('/createLink')) {
                Boolean anonymous = req.getBody().contains('anonymous');
                Integer status = anonymous ? anonymousLinkStatus : 201;
                res.setStatusCode(status);
                res.setBody(status == 201
                    ? '{"link":{"webUrl":"' + LINK_URL + '","scope":"' + (anonymous ? 'anonymous' : 'organization') + '"}}'
                    : '{"error":{"code":"' + (status == 403 ? 'accessDenied' : 'activityLimitReached') + '"}}');
            } else if (req.getMethod() == 'POST' && url.endsWith('/children')) {
                folderNames.add((String) ((Map<String, Object>) JSON.deserializeUntyped(req.getBody())).get('name'));
                res.setStatusCode(201);
                res.setBody('{"id":"NEW-FOLDER-' + folderNames.size() + '"}');
            } else if (req.getMethod() == 'GET' && url.contains('/children?')) {
                res.setStatusCode(200);
                res.setBody('{"value":[{"id":"A","file":{"mimeType":"application/pdf"}},{"id":"B","folder":{"childCount":0}},'
                    + '{"id":"C","file":{"mimeType":"image/png"}}]}');
            } else if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{"id":"ITEM-1","name":"Site Plan 1.pdf","size":10,"@microsoft.graph.downloadUrl":"https://' + HOST
                    + '/download.aspx?x=1","parentReference":{"id":"' + itemParentId + '"}}');
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":{"code":"itemNotFound"}}');
            }
            return res;
        }
    }

    @testSetup
    static void setup() {
        Project__c project = new Project__c(Name = 'Victoria Golf Resort', Email__c = 'projects@example.com', Location__Latitude__s = 6.9271, Location__Longitude__s = 79.8612);
        insert project;
        Document__c ready = new Document__c(Name = 'Marketing', Project__c = project.Id, Document_Id__c = FOLDER_ID);
        Document__c pending = new Document__c(Name = 'Legal', Project__c = project.Id);
        insert new List<Document__c>{ ready, pending };
        insert new Sub_Document__c(Name = 'brochure.pdf', Document__c = ready.Id, File_URL__c = LINK_URL);
    }

    private static Document__c document(String name) {
        return [SELECT Id, Project__c FROM Document__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1];
    }

    // A test library id, so the tests never look up the library
    private static GraphMock mockGraph(Integer anonymousLinkStatus, String itemParentId) {
        SharePointService.testDriveId = DRIVE_ID;
        GraphMock graph = new GraphMock(anonymousLinkStatus, itemParentId);
        Test.setMock(HttpCalloutMock.class, graph);
        return graph;
    }

    @isTest
    static void listsFoldersAndFilesForAnyRecordByDetectingTheLookup() {
        Id projectId = document('Marketing').Project__c;

        Test.startTest();
        List<SharePointDocumentManagerController.DocumentFolder> folders = SharePointDocumentManagerController.getDocuments(projectId, null);
        Test.stopTest();

        System.assertEquals(2, folders.size());
        SharePointDocumentManagerController.DocumentFolder marketing = folders[0].name == 'Marketing' ? folders[0] : folders[1];
        SharePointDocumentManagerController.DocumentFolder legal = folders[0].name == 'Legal' ? folders[0] : folders[1];
        System.assertEquals(true, marketing.hasFolder);
        System.assertEquals(1, marketing.files.size());
        System.assertEquals('brochure.pdf', marketing.files[0].name);
        System.assertEquals(LINK_URL, marketing.files[0].url);
        System.assertEquals(false, legal.hasFolder, 'Legal has no SharePoint folder yet');
        System.assertEquals(0, legal.files.size());
    }

    @isTest
    static void listsSubFoldersInsideTheirParentFolder() {
        Document__c marketing = document('Marketing');
        Document__c configurations = new Document__c(Name = 'Project Configurations', Project__c = marketing.Project__c, Document_Id__c = 'FOLDER-CONFIGURATIONS');
        insert configurations;
        Document__c second = new Document__c(Name = 'PC-0002 - Victoria Golf Resort - 3 BR', Parent_Document__c = configurations.Id, Document_Id__c = 'FOLDER-PC-2');
        Document__c first = new Document__c(Name = 'PC-0001 - Victoria Golf Resort - 2 BR', Parent_Document__c = configurations.Id, Document_Id__c = 'FOLDER-PC-1');
        // Linked to the project as well, yet it belongs inside its parent
        Document__c alsoLinked = new Document__c(Name = 'PC-0003 - Victoria Golf Resort - 4 BR', Parent_Document__c = configurations.Id, Project__c = marketing.Project__c);
        insert new List<Document__c>{ second, first, alsoLinked };
        insert new Sub_Document__c(Name = 'price-sheet.pdf', Document__c = first.Id, File_URL__c = LINK_URL);

        Test.startTest();
        List<SharePointDocumentManagerController.DocumentFolder> folders = SharePointDocumentManagerController.getDocuments(marketing.Project__c, null);
        Test.stopTest();

        System.assertEquals(3, folders.size(), 'Marketing, Legal and Project Configurations; sub-folders are not listed at the top');
        SharePointDocumentManagerController.DocumentFolder parent;
        for (SharePointDocumentManagerController.DocumentFolder folder : folders) {
            if (folder.name == 'Project Configurations') {
                parent = folder;
            }
        }
        System.assertNotEquals(null, parent);
        System.assertEquals(0, parent.files.size());
        System.assertEquals(3, parent.folders.size());
        System.assertEquals('PC-0001 - Victoria Golf Resort - 2 BR', parent.folders[0].name, 'Sorted by name');
        System.assertEquals(1, parent.folders[0].files.size());
        System.assertEquals('price-sheet.pdf', parent.folders[0].files[0].name);
        System.assertEquals(0, parent.folders[1].files.size());
        System.assertEquals(false, parent.folders[2].hasFolder, 'PC-0003 has no SharePoint folder yet');
    }

    @isTest
    static void usesAnExplicitLookupField() {
        Id projectId = document('Marketing').Project__c;

        Test.startTest();
        List<SharePointDocumentManagerController.DocumentFolder> folders = SharePointDocumentManagerController.getDocuments(projectId, 'Project__c');
        Test.stopTest();

        System.assertEquals(2, folders.size());
    }

    @isTest
    static void rejectsALookupThatDoesNotPointToTheObject() {
        Id projectId = document('Marketing').Project__c;
        Boolean rejected = false;

        Test.startTest();
        try {
            SharePointDocumentManagerController.getDocuments(projectId, 'Account__c');
        } catch (AuraHandledException e) {
            rejected = e.getMessage().contains('is not a Document lookup');
        }
        Test.stopTest();

        System.assert(rejected, 'A lookup to another object must be rejected');
    }

    @isTest
    static void explainsWhenDocumentsAreNotLinkedToTheObject() {
        Boolean explained = false;

        Test.startTest();
        try {
            // Document__c has no lookup to User
            SharePointDocumentManagerController.getDocuments(UserInfo.getUserId(), null);
        } catch (AuraHandledException e) {
            explained = e.getMessage().contains('Documents are not linked to');
        }
        Test.stopTest();

        System.assert(explained, 'Objects without a Document lookup should get a clear message');
    }

    @isTest
    static void createsUploadSessionInTheDocumentFolder() {
        GraphMock graph = mockGraph(201, FOLDER_ID);

        Test.startTest();
        String uploadUrl = SharePointDocumentManagerController.createUploadSession(document('Marketing').Id, 'Site Plan.pdf');
        Test.stopTest();

        System.assertEquals(UPLOAD_URL, uploadUrl);
        System.assertEquals(new List<String>{ 'POST ' + LIBRARY + '/items/' + FOLDER_ID + ':/Site%20Plan.pdf:/createUploadSession' }, graph.calls,
            'Started inside the Document\'s folder in the SharePoint library');
        System.assertEquals(0, graph.graphCallsOutsideCredential);
    }

    @isTest
    static void shortensLongFileNamesButKeepsTheExtension() {
        String longName = 'Victoria Golf Resort - 3.5 BR Sky Villa - Price Sheet - October 2026 (revised).pdf';

        String cleaned = SharePointDocumentManagerController.cleanFileName(longName);

        System.assert(cleaned.length() <= 70, 'Fits a Sub Document name even after SharePoint adds " 1": ' + cleaned.length());
        System.assert(cleaned.startsWith('Victoria Golf Resort - 3.5 BR Sky Villa'), cleaned);
        System.assert(cleaned.endsWith('.pdf'), 'The extension is kept: ' + cleaned);
        System.assertEquals('Site Plan_ Phase 1.pdf', SharePointDocumentManagerController.cleanFileName(' Site Plan: Phase 1.pdf '),
            'Short names only lose the characters SharePoint refuses');
    }

    @isTest
    static void rejectsUnsupportedFileTypes() {
        mockGraph(201, FOLDER_ID);
        Boolean rejected = false;

        Test.startTest();
        try {
            SharePointDocumentManagerController.createUploadSession(document('Marketing').Id, 'notes.docx');
        } catch (AuraHandledException e) {
            rejected = e.getMessage().contains('PDF, JPG, JPEG, PNG and MP4');
        }
        Test.stopTest();

        System.assert(rejected, 'Only PDF, JPG, JPEG, PNG and MP4 files are allowed');
    }

    @isTest
    static void rejectsFoldersNotCreatedYet() {
        mockGraph(201, FOLDER_ID);
        Boolean rejected = false;

        Test.startTest();
        try {
            SharePointDocumentManagerController.createUploadSession(document('Legal').Id, 'contract.pdf');
        } catch (AuraHandledException e) {
            rejected = e.getMessage().contains('not ready in SharePoint');
        }
        Test.stopTest();

        System.assert(rejected, 'Documents without a SharePoint folder cannot receive uploads');
    }

    @isTest
    static void uploadsChunksUntilSharePointConfirmsTheFile() {
        GraphMock graph = mockGraph(201, FOLDER_ID);
        String half = EncodingUtil.base64Encode(Blob.valueOf('12345'));

        Test.startTest();
        SharePointDocumentManagerController.ChunkResult first = SharePointDocumentManagerController.uploadChunk(UPLOAD_URL, half, 0, 5, 10);
        SharePointDocumentManagerController.ChunkResult last = SharePointDocumentManagerController.uploadChunk(UPLOAD_URL, half, 5, 10, 10);
        Test.stopTest();

        System.assertEquals(false, first.complete);
        System.assertEquals(true, last.complete);
        System.assertEquals('ITEM-1', last.itemId);
        System.assertEquals(0, graph.rangesThroughCredential, 'Upload sessions are pre-signed; ranges go straight to them');
    }

    @isTest
    static void refusesUploadUrlsOutsideTheSharePointHost() {
        List<String> badUrls = new List<String>{
            'https://example.com/upload',
            'https://api.stripe.com?.sharepoint.com',
            'https://' + HOST + '@evil.com/upload',
            'https://' + HOST + '.evil.com/upload',
            'https://other.sharepoint.com/upload',
            'http://' + HOST + '/upload'
        };
        Integer rejected = 0;

        Test.startTest();
        for (String url : badUrls) {
            try {
                SharePointDocumentManagerController.uploadChunk(url, 'AAAA', 0, 3, 3);
            } catch (AuraHandledException e) {
                rejected++;
            }
        }
        Test.stopTest();

        System.assertEquals(badUrls.size(), rejected, 'Only the SharePoint host may be called');
        System.assert(SharePointDocumentManagerController.isDriveUrl(UPLOAD_URL), 'The host\'s own upload sessions are accepted');
        System.assert(SharePointDocumentManagerController.isDriveUrl('https://' + HOST.toUpperCase() + '/:b:/s/JKPConnectDataHub/abc'),
            'Host names are not case-sensitive');
    }

    @isTest
    static void savesSubDocumentUnderTheDocumentWithPublicLink() {
        GraphMock graph = mockGraph(201, FOLDER_ID);
        Document__c doc = document('Marketing');

        Test.startTest();
        SharePointDocumentManagerController.UploadResult result = SharePointDocumentManagerController.saveSubDocument(doc.Id, 'ITEM-1', 'Site Plan.pdf');
        Test.stopTest();

        System.assertEquals(true, result.isPublic);
        System.assertEquals(LINK_URL, result.fileUrl);
        Sub_Document__c saved = [SELECT Name, Document__c, Project__c, File_URL__c, Public_Link__c FROM Sub_Document__c WHERE Id = :result.subDocumentId WITH SYSTEM_MODE];
        System.assertEquals('Site Plan 1.pdf', saved.Name, 'Name should match the file SharePoint stored');
        System.assertEquals(doc.Id, saved.Document__c);
        System.assertEquals(null, saved.Project__c, 'Uploads are linked to their Document only');
        System.assertEquals(LINK_URL, saved.File_URL__c);
        System.assertEquals(true, saved.Public_Link__c, 'An "Anyone" link opens without a Microsoft sign-in');
        System.assertEquals(new List<String>{
            'GET ' + LIBRARY + '/items/ITEM-1?$select=id,name,parentReference',
            'POST ' + LIBRARY + '/items/ITEM-1/createLink'
        }, graph.calls);
    }

    @isTest
    static void fallsBackToOrganizationLinkWhenPublicLinksAreBlocked() {
        mockGraph(403, FOLDER_ID);

        Test.startTest();
        SharePointDocumentManagerController.UploadResult result = SharePointDocumentManagerController.saveSubDocument(document('Marketing').Id, 'ITEM-1', 'photo.jpg');
        Test.stopTest();

        System.assertEquals(false, result.isPublic);
        Sub_Document__c saved = [SELECT Public_Link__c FROM Sub_Document__c WHERE Id = :result.subDocumentId WITH SYSTEM_MODE];
        System.assertEquals(false, saved.Public_Link__c, 'An organization link needs a Microsoft sign-in');
    }

    @isTest
    static void throttlingFailsTheFileInsteadOfSavingASignInLink() {
        mockGraph(429, FOLDER_ID);
        Boolean failed = false;

        Test.startTest();
        try {
            SharePointDocumentManagerController.saveSubDocument(document('Marketing').Id, 'ITEM-1', 'photo.jpg');
        } catch (AuraHandledException e) {
            failed = e.getMessage().contains('429');
        }
        Test.stopTest();

        System.assert(failed, 'A throttled link request should fail so the file can be retried');
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WITH SYSTEM_MODE], 'No Sub Document should be saved');
    }

    @isTest
    static void refusesFilesOutsideTheSelectedFolder() {
        mockGraph(201, 'SOME-OTHER-FOLDER');
        Boolean rejected = false;

        Test.startTest();
        try {
            SharePointDocumentManagerController.saveSubDocument(document('Marketing').Id, 'ITEM-1', 'photo.jpg');
        } catch (AuraHandledException e) {
            rejected = e.getMessage().contains('not in the selected folder');
        }
        Test.stopTest();

        System.assert(rejected, 'A file from another folder must not be linked');
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WITH SYSTEM_MODE], 'Only the setup Sub Document should exist');
    }

    // Answers the lookups and the delete that deleteFile makes, and records which calls were made
    private class FileDeleteMock implements HttpCalloutMock {
        private Integer byNameStatus;
        private Integer byLinkStatus;
        private String parentId;
        private Boolean isFolder;
        private Integer deleteStatus;
        public List<String> calls = new List<String>();
        public List<String> urls = new List<String>();

        FileDeleteMock(Integer byNameStatus, Integer byLinkStatus, String parentId, Boolean isFolder, Integer deleteStatus) {
            this.byNameStatus = byNameStatus;
            this.byLinkStatus = byLinkStatus;
            this.parentId = parentId;
            this.isFolder = isFolder;
            this.deleteStatus = deleteStatus;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = req.getEndpoint();
            Boolean byLink = url.contains('/shares/');
            // A lookup by name addresses the folder, then ':/' and the file name; everything else is the item itself
            calls.add(req.getMethod() + (byLink ? ' share' : url.substringAfter('/items/').contains(':/') ? ' name' : ' item'));
            urls.add(url);
            if (req.getMethod() == 'DELETE') {
                res.setStatusCode(deleteStatus);
                return res;
            }
            Integer status = byLink ? byLinkStatus : byNameStatus;
            res.setStatusCode(status);
            res.setBody(status == 200
                ? '{"id":"ITEM-9","parentReference":{"id":"' + parentId + '"},' + (isFolder ? '"folder":{"childCount":0}' : '"file":{"mimeType":"application/pdf"}') + '}'
                : '{"error":{"code":"itemNotFound"}}');
            return res;
        }
    }

    private static Id brochureId() {
        return [SELECT Id FROM Sub_Document__c WHERE Name = 'brochure.pdf' WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static FileDeleteMock mockDelete(Integer byNameStatus, Integer byLinkStatus, String parentId, Boolean isFolder, Integer deleteStatus) {
        SharePointService.testDriveId = DRIVE_ID;
        FileDeleteMock graph = new FileDeleteMock(byNameStatus, byLinkStatus, parentId, isFolder, deleteStatus);
        Test.setMock(HttpCalloutMock.class, graph);
        return graph;
    }

    // The message shown to the user, or null when the file was deleted
    private static String deleteError(Id subDocumentId) {
        try {
            SharePointDocumentManagerController.deleteFile(subDocumentId);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    private static SharePointDocumentManagerController.FileItem listedFile(Id projectId, Id fileId) {
        for (SharePointDocumentManagerController.DocumentFolder folder : SharePointDocumentManagerController.getDocuments(projectId, null)) {
            for (SharePointDocumentManagerController.FileItem file : folder.files) {
                if (file.id == fileId) {
                    return file;
                }
            }
        }
        return null;
    }

    private static User minimumAccessUser(String alias) {
        Profile minimumAccess = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        User user = new User(
            Alias = alias,
            Email = alias + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Tester ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = minimumAccess.Id,
            TimeZoneSidKey = 'Asia/Colombo',
            Username = alias + '.' + System.currentTimeMillis() + '@example.com'
        );
        insert user;
        return user;
    }

    @isTest
    static void deletesTheFileInSharePointAndItsRecord() {
        Id brochure = brochureId();
        Project_Configuration__c config = new Project_Configuration__c(Project__c = document('Marketing').Project__c, Unit_Type__c = '2 BR', Sub_Document__c = brochure);
        insert config;
        String configName = [SELECT Name FROM Project_Configuration__c WHERE Id = :config.Id WITH SYSTEM_MODE].Name;
        FileDeleteMock graph = mockDelete(404, 200, FOLDER_ID, false, 204);

        Test.startTest();
        SharePointDocumentManagerController.FileItem listed = listedFile(config.Project__c, brochure);
        String error = deleteError(brochure);
        Test.stopTest();

        System.assert(listed.canDelete, 'The owner may delete the file');
        System.assertEquals(new List<String>{ configName }, listed.linkedConfigurations, 'The configuration that shows the file is named');
        System.assertEquals(null, error);
        System.assertEquals(new List<String>{ 'GET share', 'DELETE item' }, graph.calls, 'Found through its share link');
        System.assertEquals('callout:SharePoint_Graph/v1.0/shares/' + SharePointDocumentManagerController.shareId(LINK_URL)
            + '/driveItem?$select=id,parentReference,file,folder', graph.urls[0]);
        System.assertEquals(LIBRARY + '/items/ITEM-9', graph.urls[1], 'Deleted from the SharePoint library');
        System.assertEquals(0, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :brochure WITH SYSTEM_MODE]);
        System.assertEquals(null, [SELECT Sub_Document__c FROM Project_Configuration__c WHERE Id = :config.Id WITH SYSTEM_MODE].Sub_Document__c,
            'The configuration no longer shows the file');
    }

    @isTest
    static void usesTheShareLinkEvenWhenAnotherFileHasTheSameName() {
        // Another file with the same name would answer a name lookup; the share link is what identifies the file
        FileDeleteMock graph = mockDelete(200, 200, FOLDER_ID, false, 204);

        Test.startTest();
        String error = deleteError(brochureId());
        Test.stopTest();

        System.assertEquals(null, error);
        System.assertEquals(new List<String>{ 'GET share', 'DELETE item' }, graph.calls, 'No lookup by name');
    }

    @isTest
    static void removesTheRecordWhenSharePointNoLongerHasTheFile() {
        FileDeleteMock graph = mockDelete(200, 404, FOLDER_ID, false, 204);

        Test.startTest();
        String error = deleteError(brochureId());
        Test.stopTest();

        System.assertEquals(null, error);
        System.assertEquals(new List<String>{ 'GET share' }, graph.calls, 'Nothing to delete in SharePoint');
        System.assertEquals(0, [SELECT COUNT() FROM Sub_Document__c WHERE Name = 'brochure.pdf' WITH SYSTEM_MODE]);
    }

    @isTest
    static void looksUpAFileWithoutALinkByName() {
        Sub_Document__c noLink = new Sub_Document__c(Name = 'site-plan.pdf', Document__c = document('Marketing').Id);
        insert noLink;
        FileDeleteMock graph = mockDelete(200, 404, FOLDER_ID, false, 204);

        Test.startTest();
        String error = deleteError(noLink.Id);
        Test.stopTest();

        System.assertEquals(null, error);
        System.assertEquals(new List<String>{ 'GET name', 'DELETE item' }, graph.calls);
        System.assertEquals(LIBRARY + '/items/' + FOLDER_ID + ':/site-plan.pdf?$select=id,parentReference,file,folder', graph.urls[0]);
        System.assertEquals(0, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :noLink.Id WITH SYSTEM_MODE]);
    }

    @isTest
    static void removesARecordWhoseLinkIsNotASharePointFile() {
        Sub_Document__c external = new Sub_Document__c(Name = 'sample.pdf', Document__c = document('Marketing').Id, File_URL__c = 'https://file-examples.com/sample.pdf');
        insert external;
        FileDeleteMock graph = mockDelete(200, 200, FOLDER_ID, false, 204);

        Test.startTest();
        String error = deleteError(external.Id);
        Test.stopTest();

        System.assertEquals(null, error);
        System.assertEquals(0, graph.calls.size(), 'SharePoint is not touched for a file that is not in it');
        System.assertEquals(0, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :external.Id WITH SYSTEM_MODE]);
    }

    @isTest
    static void neverDeletesFoldersOrFilesOutsideTheirFolder() {
        Id brochure = brochureId();

        Test.startTest();
        FileDeleteMock folder = mockDelete(404, 200, FOLDER_ID, true, 204);
        String folderError = deleteError(brochure);
        FileDeleteMock elsewhere = mockDelete(404, 200, 'SOME-OTHER-FOLDER', false, 204);
        String elsewhereError = deleteError(brochure);
        String notAFile = deleteError(document('Marketing').Id);
        Test.stopTest();

        System.assert(folderError != null && folderError.contains('not folders'), folderError);
        System.assert(elsewhereError != null && elsewhereError.contains('no longer in its folder'), elsewhereError);
        System.assert(notAFile != null && notAFile.contains('Choose a file'), notAFile);
        System.assert(!folder.calls.contains('DELETE item') && !elsewhere.calls.contains('DELETE item'), 'Nothing was deleted in SharePoint');
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :brochure WITH SYSTEM_MODE], 'The record is kept');
    }

    @isTest
    static void keepsTheRecordWhenSharePointCannotDeleteTheFile() {
        mockDelete(404, 200, FOLDER_ID, false, 503);

        Test.startTest();
        String error = deleteError(brochureId());
        Test.stopTest();

        System.assert(error != null && error.contains('could not delete'), error);
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WHERE Name = 'brochure.pdf' WITH SYSTEM_MODE]);
    }

    @isTest
    static void saysSoWhenTheFileWasAlreadyDeleted() {
        Id brochure = brochureId();
        delete new Sub_Document__c(Id = brochure);
        FileDeleteMock graph = mockDelete(404, 200, FOLDER_ID, false, 204);

        Test.startTest();
        String error = deleteError(brochure);
        Test.stopTest();

        System.assert(error != null && error.contains('already deleted'), error);
        System.assertEquals(0, graph.calls.size());
    }

    @isTest
    static void refusesUsersWhoCannotDeleteFiles() {
        User viewer = minimumAccessUser('dmnodel');
        Id brochure = brochureId();
        Id projectId = document('Marketing').Project__c;
        FileDeleteMock graph = mockDelete(404, 200, FOLDER_ID, false, 204);
        String error;
        SharePointDocumentManagerController.FileItem listed;

        Test.startTest();
        System.runAs(viewer) {
            listed = listedFile(projectId, brochure);
            error = deleteError(brochure);
        }
        Test.stopTest();

        System.assert(error != null && error.contains('permission'), error);
        System.assertEquals(0, graph.calls.size(), 'SharePoint is not touched');
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :brochure WITH SYSTEM_MODE]);
        System.assertEquals(false, listed.canDelete, 'The delete button is not offered');
    }

    @isTest
    static void offersDeleteOnlyForFilesTheUserMayDelete() {
        // Delete permission on Sub Documents, but the brochure belongs to another user
        User member = minimumAccessUser('dmmember');
        PermissionSet canDelete = new PermissionSet(Name = 'Sub_Document_Delete_Test', Label = 'Sub Document Delete Test');
        insert canDelete;
        insert new ObjectPermissions(ParentId = canDelete.Id, SobjectType = 'Sub_Document__c',
            PermissionsRead = true, PermissionsEdit = true, PermissionsDelete = true);
        insert new PermissionSetAssignment(AssigneeId = member.Id, PermissionSetId = canDelete.Id);
        Id brochure = brochureId();
        Id projectId = document('Marketing').Project__c;
        FileDeleteMock graph = mockDelete(404, 200, FOLDER_ID, false, 204);
        String error;
        SharePointDocumentManagerController.FileItem listed;

        Test.startTest();
        System.runAs(member) {
            listed = listedFile(projectId, brochure);
            error = deleteError(brochure);
        }
        Test.stopTest();

        System.assertEquals(false, listed.canDelete, 'No button for a file the user cannot delete');
        System.assert(error != null && error.contains('permission'), error);
        System.assertEquals(0, graph.calls.size());
    }

    @isTest
    static void addressesShareLinksTheWayGraphExpects() {
        System.assertEquals('u!aHR0cHM6Ly9rZWVsbHMuc2hhcmVwb2ludC5jb20vOmI6L3MvSktQQ29ubmVjdERhdGFIdWIvYWJj',
            SharePointDocumentManagerController.shareId('https://keells.sharepoint.com/:b:/s/JKPConnectDataHub/abc'));
    }

    @isTest
    static void createsFoldersAtTheTopOfTheLibraryOrInsideTheirParent() {
        GraphMock graph = mockGraph(201, FOLDER_ID);

        Test.startTest();
        String top = SharePointDocumentManagerController.createFolder('', 'M/s Perera Holdings');
        String inside = SharePointDocumentManagerController.createFolder('PARENT-1', 'Legal');
        Test.stopTest();

        System.assertEquals('NEW-FOLDER-1', top);
        System.assertEquals('NEW-FOLDER-2', inside);
        System.assertEquals(new List<String>{ 'POST ' + LIBRARY + '/root/children', 'POST ' + LIBRARY + '/items/PARENT-1/children' }, graph.calls);
        System.assertEquals(new List<String>{ 'M_s Perera Holdings', 'Legal' }, graph.folderNames, 'Names SharePoint refuses are cleaned first');
        System.assertEquals(0, graph.graphCallsOutsideCredential);
    }

    @isTest
    static void uploadsABase64FileAndLinksItWithoutSavingARecord() {
        GraphMock graph = mockGraph(201, FOLDER_ID);
        String tenBytes = EncodingUtil.base64Encode(Blob.valueOf('1234567890'));
        String unreadable;

        Test.startTest();
        String itemId = SharePointDocumentManagerController.uploadBase64(FOLDER_ID, 'Site Plan.pdf', tenBytes, true);
        SharePointDocumentManagerController.UploadResult linked = SharePointDocumentManagerController.linkFile(FOLDER_ID, itemId);
        Integer files = SharePointDocumentManagerController.countFiles(FOLDER_ID);
        try {
            SharePointDocumentManagerController.uploadBase64(FOLDER_ID, 'empty.pdf', '', true);
        } catch (AuraHandledException e) {
            unreadable = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals('ITEM-1', itemId);
        System.assertEquals(LINK_URL, linked.fileUrl);
        System.assertEquals(true, linked.isPublic);
        System.assertEquals('Site Plan 1.pdf', linked.storedName);
        System.assertEquals(2, files, 'Only files are counted, not folders');
        System.assert(graph.calls.contains('GET ' + LIBRARY + '/items/' + FOLDER_ID + '/children?$select=id,file&$top=200'), graph.calls);
        System.assert(unreadable != null && unreadable.contains('could not be read'), unreadable);
        System.assertEquals(0, graph.rangesThroughCredential);
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WITH SYSTEM_MODE], 'No Sub Document is saved');
    }

    @isTest
    static void readsTheFileBehindALink() {
        GraphMock graph = mockGraph(201, FOLDER_ID);

        Test.startTest();
        SharePointDocumentManagerController.DriveFile file = SharePointDocumentManagerController.fileBehindLink(LINK_URL);
        Test.stopTest();

        System.assertEquals('Site Plan 1.pdf', file.name);
        System.assertEquals(10L, file.size);
        System.assertEquals('https://' + HOST + '/download.aspx?x=1', file.downloadUrl);
        System.assertEquals(new List<String>{
            'GET callout:SharePoint_Graph/v1.0/shares/' + SharePointDocumentManagerController.shareId(LINK_URL) + '/driveItem'
        }, graph.calls);
    }

    @isTest
    static void givesTheUploadLimitFromTheSharePointSetting() {
        Long limitBytes = SharePointDocumentManagerController.getMaxUploadBytes();

        System.assertEquals(SharePointService.maxUploadBytes(), limitBytes);
        System.assert(limitBytes > 0 && Math.mod(limitBytes, 1048576) == 0, 'Whole megabytes: ' + limitBytes);
    }
}