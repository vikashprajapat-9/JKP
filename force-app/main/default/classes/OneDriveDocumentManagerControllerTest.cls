@isTest
private class OneDriveDocumentManagerControllerTest {

    private static final String FOLDER_ID = 'FOLDER-1';
    private static final String UPLOAD_URL = 'https://utillabs-my.sharepoint.com/personal/test/_api/v2.0/drive/items/X/uploadSession?guid=1';
    private static final String LINK_URL = 'https://utillabs-my.sharepoint.com/:b:/g/personal/test/abc';

    // Answers every Microsoft Graph call the controller makes
    private class GraphMock implements HttpCalloutMock {
        private Integer anonymousLinkStatus;
        private String itemParentId;

        GraphMock(Integer anonymousLinkStatus, String itemParentId) {
            this.anonymousLinkStatus = anonymousLinkStatus;
            this.itemParentId = itemParentId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = req.getEndpoint();
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
            } else if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{"id":"ITEM-1","name":"Site Plan 1.pdf","parentReference":{"id":"' + itemParentId + '"}}');
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":{"code":"itemNotFound"}}');
            }
            return res;
        }
    }

    @testSetup
    static void setup() {
        Project__c project = new Project__c(Name = 'Victoria Golf Resort');
        insert project;
        Document__c ready = new Document__c(Name = 'Marketing', Project__c = project.Id, Document_Id__c = FOLDER_ID);
        Document__c pending = new Document__c(Name = 'Legal', Project__c = project.Id);
        insert new List<Document__c>{ ready, pending };
        insert new Sub_Document__c(Name = 'brochure.pdf', Document__c = ready.Id, File_URL__c = LINK_URL);
    }

    private static Document__c document(String name) {
        return [SELECT Id, Project__c FROM Document__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1];
    }

    // Skips the real token call so the tests do not depend on the org's OneDriveAuthSetting__mdt record
    private static void mockGraph(Integer anonymousLinkStatus, String itemParentId) {
        OneDriveDocumentManagerController.accessToken = 'test-token';
        Test.setMock(HttpCalloutMock.class, new GraphMock(anonymousLinkStatus, itemParentId));
    }

    @isTest
    static void listsFoldersAndFilesForAnyRecordByDetectingTheLookup() {
        Id projectId = document('Marketing').Project__c;

        Test.startTest();
        List<OneDriveDocumentManagerController.DocumentFolder> folders = OneDriveDocumentManagerController.getDocuments(projectId, null);
        Test.stopTest();

        System.assertEquals(2, folders.size());
        OneDriveDocumentManagerController.DocumentFolder marketing = folders[0].name == 'Marketing' ? folders[0] : folders[1];
        OneDriveDocumentManagerController.DocumentFolder legal = folders[0].name == 'Legal' ? folders[0] : folders[1];
        System.assertEquals(true, marketing.hasFolder);
        System.assertEquals(1, marketing.files.size());
        System.assertEquals('brochure.pdf', marketing.files[0].name);
        System.assertEquals(LINK_URL, marketing.files[0].url);
        System.assertEquals(false, legal.hasFolder, 'Legal has no OneDrive folder yet');
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
        List<OneDriveDocumentManagerController.DocumentFolder> folders = OneDriveDocumentManagerController.getDocuments(marketing.Project__c, null);
        Test.stopTest();

        System.assertEquals(3, folders.size(), 'Marketing, Legal and Project Configurations; sub-folders are not listed at the top');
        OneDriveDocumentManagerController.DocumentFolder parent;
        for (OneDriveDocumentManagerController.DocumentFolder folder : folders) {
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
        System.assertEquals(false, parent.folders[2].hasFolder, 'PC-0003 has no OneDrive folder yet');
    }

    @isTest
    static void usesAnExplicitLookupField() {
        Id projectId = document('Marketing').Project__c;

        Test.startTest();
        List<OneDriveDocumentManagerController.DocumentFolder> folders = OneDriveDocumentManagerController.getDocuments(projectId, 'Project__c');
        Test.stopTest();

        System.assertEquals(2, folders.size());
    }

    @isTest
    static void rejectsALookupThatDoesNotPointToTheObject() {
        Id projectId = document('Marketing').Project__c;
        Boolean rejected = false;

        Test.startTest();
        try {
            OneDriveDocumentManagerController.getDocuments(projectId, 'Account__c');
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
            OneDriveDocumentManagerController.getDocuments(UserInfo.getUserId(), null);
        } catch (AuraHandledException e) {
            explained = e.getMessage().contains('Documents are not linked to');
        }
        Test.stopTest();

        System.assert(explained, 'Objects without a Document lookup should get a clear message');
    }

    @isTest
    static void createsUploadSessionInTheDocumentFolder() {
        mockGraph(201, FOLDER_ID);

        Test.startTest();
        String uploadUrl = OneDriveDocumentManagerController.createUploadSession(document('Marketing').Id, 'Site Plan.pdf');
        Test.stopTest();

        System.assertEquals(UPLOAD_URL, uploadUrl);
    }

    @isTest
    static void shortensLongFileNamesButKeepsTheExtension() {
        String longName = 'Victoria Golf Resort - 3.5 BR Sky Villa - Price Sheet - October 2026 (revised).pdf';

        String cleaned = OneDriveDocumentManagerController.cleanFileName(longName);

        System.assert(cleaned.length() <= 70, 'Fits a Sub Document name even after OneDrive adds " 1": ' + cleaned.length());
        System.assert(cleaned.startsWith('Victoria Golf Resort - 3.5 BR Sky Villa'), cleaned);
        System.assert(cleaned.endsWith('.pdf'), 'The extension is kept: ' + cleaned);
        System.assertEquals('Site Plan_ Phase 1.pdf', OneDriveDocumentManagerController.cleanFileName(' Site Plan: Phase 1.pdf '),
            'Short names only lose the characters OneDrive refuses');
    }

    @isTest
    static void rejectsUnsupportedFileTypes() {
        mockGraph(201, FOLDER_ID);
        Boolean rejected = false;

        Test.startTest();
        try {
            OneDriveDocumentManagerController.createUploadSession(document('Marketing').Id, 'notes.docx');
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
            OneDriveDocumentManagerController.createUploadSession(document('Legal').Id, 'contract.pdf');
        } catch (AuraHandledException e) {
            rejected = e.getMessage().contains('not ready');
        }
        Test.stopTest();

        System.assert(rejected, 'Documents without a OneDrive folder cannot receive uploads');
    }

    @isTest
    static void uploadsChunksUntilOneDriveConfirmsTheFile() {
        mockGraph(201, FOLDER_ID);
        String half = EncodingUtil.base64Encode(Blob.valueOf('12345'));

        Test.startTest();
        OneDriveDocumentManagerController.ChunkResult first = OneDriveDocumentManagerController.uploadChunk(UPLOAD_URL, half, 0, 5, 10);
        OneDriveDocumentManagerController.ChunkResult last = OneDriveDocumentManagerController.uploadChunk(UPLOAD_URL, half, 5, 10, 10);
        Test.stopTest();

        System.assertEquals(false, first.complete);
        System.assertEquals(true, last.complete);
        System.assertEquals('ITEM-1', last.itemId);
    }

    @isTest
    static void refusesUploadUrlsOutsideTheDriveHost() {
        List<String> badUrls = new List<String>{
            'https://example.com/upload',
            'https://api.stripe.com?.sharepoint.com',
            'https://utillabs-my.sharepoint.com@evil.com/upload',
            'https://other-my.sharepoint.com/upload',
            'http://utillabs-my.sharepoint.com/upload'
        };
        Integer rejected = 0;

        Test.startTest();
        for (String url : badUrls) {
            try {
                OneDriveDocumentManagerController.uploadChunk(url, 'AAAA', 0, 3, 3);
            } catch (AuraHandledException e) {
                rejected++;
            }
        }
        Test.stopTest();

        System.assertEquals(badUrls.size(), rejected, 'Only the drive\'s own upload host may be called');
    }

    @isTest
    static void savesSubDocumentUnderTheDocumentWithPublicLink() {
        mockGraph(201, FOLDER_ID);
        Document__c doc = document('Marketing');

        Test.startTest();
        OneDriveDocumentManagerController.UploadResult result = OneDriveDocumentManagerController.saveSubDocument(doc.Id, 'ITEM-1', 'Site Plan.pdf');
        Test.stopTest();

        System.assertEquals(true, result.isPublic);
        System.assertEquals(LINK_URL, result.fileUrl);
        Sub_Document__c saved = [SELECT Name, Document__c, Project__c, File_URL__c FROM Sub_Document__c WHERE Id = :result.subDocumentId WITH SYSTEM_MODE];
        System.assertEquals('Site Plan 1.pdf', saved.Name, 'Name should match the file OneDrive stored');
        System.assertEquals(doc.Id, saved.Document__c);
        System.assertEquals(null, saved.Project__c, 'Uploads are linked to their Document only');
        System.assertEquals(LINK_URL, saved.File_URL__c);
    }

    @isTest
    static void fallsBackToOrganizationLinkWhenPublicLinksAreBlocked() {
        mockGraph(403, FOLDER_ID);

        Test.startTest();
        OneDriveDocumentManagerController.UploadResult result = OneDriveDocumentManagerController.saveSubDocument(document('Marketing').Id, 'ITEM-1', 'photo.jpg');
        Test.stopTest();

        System.assertEquals(false, result.isPublic);
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :result.subDocumentId WITH SYSTEM_MODE]);
    }

    @isTest
    static void throttlingFailsTheFileInsteadOfSavingASignInLink() {
        mockGraph(429, FOLDER_ID);
        Boolean failed = false;

        Test.startTest();
        try {
            OneDriveDocumentManagerController.saveSubDocument(document('Marketing').Id, 'ITEM-1', 'photo.jpg');
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
            OneDriveDocumentManagerController.saveSubDocument(document('Marketing').Id, 'ITEM-1', 'photo.jpg');
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
            calls.add(req.getMethod() + (byLink ? ' share' : url.substringAfter('/drive/items/').contains(':/') ? ' name' : ' item'));
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
        OneDriveDocumentManagerController.accessToken = 'test-token';
        FileDeleteMock graph = new FileDeleteMock(byNameStatus, byLinkStatus, parentId, isFolder, deleteStatus);
        Test.setMock(HttpCalloutMock.class, graph);
        return graph;
    }

    // The message shown to the user, or null when the file was deleted
    private static String deleteError(Id subDocumentId) {
        try {
            OneDriveDocumentManagerController.deleteFile(subDocumentId);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    private static OneDriveDocumentManagerController.FileItem listedFile(Id projectId, Id fileId) {
        for (OneDriveDocumentManagerController.DocumentFolder folder : OneDriveDocumentManagerController.getDocuments(projectId, null)) {
            for (OneDriveDocumentManagerController.FileItem file : folder.files) {
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
    static void deletesTheFileInOneDriveAndItsRecord() {
        Id brochure = brochureId();
        Project_Configuration__c config = new Project_Configuration__c(Project__c = document('Marketing').Project__c, Unit_Type__c = '2 BR', Sub_Document__c = brochure);
        insert config;
        String configName = [SELECT Name FROM Project_Configuration__c WHERE Id = :config.Id WITH SYSTEM_MODE].Name;
        FileDeleteMock graph = mockDelete(404, 200, FOLDER_ID, false, 204);

        Test.startTest();
        OneDriveDocumentManagerController.FileItem listed = listedFile(config.Project__c, brochure);
        String error = deleteError(brochure);
        Test.stopTest();

        System.assert(listed.canDelete, 'The owner may delete the file');
        System.assertEquals(new List<String>{ configName }, listed.linkedConfigurations, 'The configuration that shows the file is named');
        System.assertEquals(null, error);
        System.assertEquals(new List<String>{ 'GET share', 'DELETE item' }, graph.calls, 'Found through its share link');
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
    static void removesTheRecordWhenOneDriveNoLongerHasTheFile() {
        FileDeleteMock graph = mockDelete(200, 404, FOLDER_ID, false, 204);

        Test.startTest();
        String error = deleteError(brochureId());
        Test.stopTest();

        System.assertEquals(null, error);
        System.assertEquals(new List<String>{ 'GET share' }, graph.calls, 'Nothing to delete in OneDrive');
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
        System.assertEquals(0, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :noLink.Id WITH SYSTEM_MODE]);
    }

    @isTest
    static void removesARecordWhoseLinkIsNotAOneDriveFile() {
        Sub_Document__c external = new Sub_Document__c(Name = 'sample.pdf', Document__c = document('Marketing').Id, File_URL__c = 'https://file-examples.com/sample.pdf');
        insert external;
        FileDeleteMock graph = mockDelete(200, 200, FOLDER_ID, false, 204);

        Test.startTest();
        String error = deleteError(external.Id);
        Test.stopTest();

        System.assertEquals(null, error);
        System.assertEquals(0, graph.calls.size(), 'OneDrive is not touched for a file that is not in it');
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
        System.assert(!folder.calls.contains('DELETE item') && !elsewhere.calls.contains('DELETE item'), 'Nothing was deleted in OneDrive');
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :brochure WITH SYSTEM_MODE], 'The record is kept');
    }

    @isTest
    static void keepsTheRecordWhenOneDriveCannotDeleteTheFile() {
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
        OneDriveDocumentManagerController.FileItem listed;

        Test.startTest();
        System.runAs(viewer) {
            listed = listedFile(projectId, brochure);
            error = deleteError(brochure);
        }
        Test.stopTest();

        System.assert(error != null && error.contains('permission'), error);
        System.assertEquals(0, graph.calls.size(), 'OneDrive is not touched');
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
        OneDriveDocumentManagerController.FileItem listed;

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
        System.assertEquals('u!aHR0cHM6Ly91dGlsbGFicy1teS5zaGFyZXBvaW50LmNvbS86YjovZy9wZXJzb25hbC90ZXN0L2FiYw', OneDriveDocumentManagerController.shareId(LINK_URL));
    }
}