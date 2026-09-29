@isTest
private class ProjectDocumentUploadControllerTest {

    private static final String FOLDER_ID = 'FOLDER-1';
    private static final String UPLOAD_URL = 'https://utillabs-my.sharepoint.com/upload/session-1';
    private static final String LINK_URL = 'https://utillabs-my.sharepoint.com/:b:/g/personal/test/abc';

    // Answers every Microsoft call the controller makes
    private class GraphMock implements HttpCalloutMock {
        private Boolean anonymousLinksAllowed;
        private String itemParentId;

        GraphMock(Boolean anonymousLinksAllowed, String itemParentId) {
            this.anonymousLinksAllowed = anonymousLinksAllowed;
            this.itemParentId = itemParentId;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = req.getEndpoint();
            if (url.contains('login.microsoftonline.com')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"test-token"}');
            } else if (url.endsWith(':/createUploadSession')) {
                res.setStatusCode(200);
                res.setBody('{"uploadUrl":"' + UPLOAD_URL + '"}');
            } else if (req.getMethod() == 'PUT') {
                Boolean lastChunk = req.getHeader('Content-Range').endsWith('-9/10');
                res.setStatusCode(lastChunk ? 201 : 202);
                res.setBody(lastChunk ? '{"id":"ITEM-1"}' : '{"nextExpectedRanges":["5-"]}');
            } else if (url.endsWith('/createLink')) {
                Boolean anonymous = req.getBody().contains('anonymous');
                res.setStatusCode(anonymous && !anonymousLinksAllowed ? 403 : 201);
                res.setBody(anonymous && !anonymousLinksAllowed
                    ? '{"error":{"code":"accessDenied"}}'
                    : '{"link":{"webUrl":"' + LINK_URL + '"}}');
            } else if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{"id":"ITEM-1","parentReference":{"id":"' + itemParentId + '"}}');
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
        insert new Sub_Document__c(Name = 'brochure.pdf', Document__c = ready.Id, Project__c = project.Id, File_URL__c = LINK_URL);
    }

    private static Document__c document(String name) {
        return [SELECT Id, Project__c FROM Document__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1];
    }

    @isTest
    static void listsProjectFoldersWithFileCounts() {
        Id projectId = document('Marketing').Project__c;

        Test.startTest();
        List<ProjectDocumentUploadController.DocumentFolder> folders = ProjectDocumentUploadController.getProjectDocuments(projectId);
        Test.stopTest();

        System.assertEquals(2, folders.size());
        System.assertEquals('Legal', folders[0].name);
        System.assertEquals(false, folders[0].hasFolder, 'Legal has no OneDrive folder yet');
        System.assertEquals(0, folders[0].fileCount);
        System.assertEquals('Marketing', folders[1].name);
        System.assertEquals(true, folders[1].hasFolder);
        System.assertEquals(1, folders[1].fileCount);
    }

    @isTest
    static void createsUploadSessionInTheDocumentFolder() {
        Test.setMock(HttpCalloutMock.class, new GraphMock(true, FOLDER_ID));

        Test.startTest();
        String uploadUrl = ProjectDocumentUploadController.createUploadSession(document('Marketing').Id, 'Site Plan.pdf');
        Test.stopTest();

        System.assertEquals(UPLOAD_URL, uploadUrl);
    }

    @isTest
    static void rejectsUnsupportedFileTypes() {
        Test.setMock(HttpCalloutMock.class, new GraphMock(true, FOLDER_ID));
        Boolean rejected = false;

        Test.startTest();
        try {
            ProjectDocumentUploadController.createUploadSession(document('Marketing').Id, 'notes.docx');
        } catch (AuraHandledException e) {
            rejected = e.getMessage().contains('PDF, JPG, JPEG, PNG and MP4');
        }
        Test.stopTest();

        System.assert(rejected, 'Only PDF, JPG, JPEG, PNG and MP4 files are allowed');
    }

    @isTest
    static void rejectsFoldersNotCreatedYet() {
        Test.setMock(HttpCalloutMock.class, new GraphMock(true, FOLDER_ID));
        Boolean rejected = false;

        Test.startTest();
        try {
            ProjectDocumentUploadController.createUploadSession(document('Legal').Id, 'contract.pdf');
        } catch (AuraHandledException e) {
            rejected = e.getMessage().contains('not ready');
        }
        Test.stopTest();

        System.assert(rejected, 'Documents without a OneDrive folder cannot receive uploads');
    }

    @isTest
    static void uploadsChunksUntilOneDriveConfirmsTheFile() {
        Test.setMock(HttpCalloutMock.class, new GraphMock(true, FOLDER_ID));
        String half = EncodingUtil.base64Encode(Blob.valueOf('12345'));

        Test.startTest();
        ProjectDocumentUploadController.ChunkResult first = ProjectDocumentUploadController.uploadChunk(UPLOAD_URL, half, 0, 5, 10);
        ProjectDocumentUploadController.ChunkResult last = ProjectDocumentUploadController.uploadChunk(UPLOAD_URL, half, 5, 10, 10);
        Test.stopTest();

        System.assertEquals(false, first.complete);
        System.assertEquals(true, last.complete);
        System.assertEquals('ITEM-1', last.itemId);
    }

    @isTest
    static void refusesUploadUrlsOutsideOneDrive() {
        Boolean rejected = false;

        Test.startTest();
        try {
            ProjectDocumentUploadController.uploadChunk('https://example.com/upload', 'AAAA', 0, 3, 3);
        } catch (AuraHandledException e) {
            rejected = true;
        }
        Test.stopTest();

        System.assert(rejected, 'Only SharePoint upload sessions may be called');
    }

    @isTest
    static void savesSubDocumentWithPublicLink() {
        Test.setMock(HttpCalloutMock.class, new GraphMock(true, FOLDER_ID));
        Document__c doc = document('Marketing');

        Test.startTest();
        ProjectDocumentUploadController.UploadResult result = ProjectDocumentUploadController.saveSubDocument(doc.Id, 'ITEM-1', 'Site Plan.pdf');
        Test.stopTest();

        System.assertEquals(true, result.isPublic);
        System.assertEquals(LINK_URL, result.fileUrl);
        Sub_Document__c saved = [SELECT Name, Document__c, Project__c, File_URL__c FROM Sub_Document__c WHERE Id = :result.subDocumentId WITH SYSTEM_MODE];
        System.assertEquals('Site Plan.pdf', saved.Name);
        System.assertEquals(doc.Id, saved.Document__c);
        System.assertEquals(doc.Project__c, saved.Project__c);
        System.assertEquals(LINK_URL, saved.File_URL__c);
    }

    @isTest
    static void fallsBackToOrganizationLinkWhenPublicLinksAreBlocked() {
        Test.setMock(HttpCalloutMock.class, new GraphMock(false, FOLDER_ID));

        Test.startTest();
        ProjectDocumentUploadController.UploadResult result = ProjectDocumentUploadController.saveSubDocument(document('Marketing').Id, 'ITEM-1', 'photo.jpg');
        Test.stopTest();

        System.assertEquals(false, result.isPublic);
        System.assertEquals(LINK_URL, result.fileUrl);
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WHERE Id = :result.subDocumentId WITH SYSTEM_MODE]);
    }

    @isTest
    static void refusesFilesOutsideTheSelectedFolder() {
        Test.setMock(HttpCalloutMock.class, new GraphMock(true, 'SOME-OTHER-FOLDER'));
        Boolean rejected = false;

        Test.startTest();
        try {
            ProjectDocumentUploadController.saveSubDocument(document('Marketing').Id, 'ITEM-1', 'photo.jpg');
        } catch (AuraHandledException e) {
            rejected = e.getMessage().contains('not in the selected folder');
        }
        Test.stopTest();

        System.assert(rejected, 'A file from another folder must not be linked');
        System.assertEquals(1, [SELECT COUNT() FROM Sub_Document__c WITH SYSTEM_MODE], 'Only the setup Sub Document should exist');
    }
}