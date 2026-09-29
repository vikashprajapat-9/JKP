@isTest
private class ProjectTriggerHandlerTest {

    // Answers the OneDrive token request; the Graph folder call itself is skipped in tests by the queueable.
    private class OneDriveMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"access_token":"test-token","id":"test-folder-id"}');
            return res;
        }
    }

    @testSetup
    static void setup() {
        Document_Master__c master = new Document_Master__c(Name = 'Project');
        insert master;
        insert new Document_category__c(Name = 'Marketing', Document_Master__c = master.Id);
    }

    @isTest
    static void insertQueuesOneFolderJobForAllProjects() {
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        List<Project__c> projects = new List<Project__c>();
        for (Integer i = 0; i < 5; i++) {
            projects.add(new Project__c(Name = 'Test Project ' + i));
        }

        Test.startTest();
        insert projects;
        Integer queuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, queuedJobs, 'One OneDrive job should be queued for the whole insert');
        System.assertEquals(5, [SELECT COUNT() FROM Project__c WITH SYSTEM_MODE], 'Projects must be saved even though folder creation runs async');
    }

    @isTest
    static void createsOneDocumentPerProjectCategory() {
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        Project__c project = new Project__c(Name = 'Skyline Towers');
        insert project;

        Test.startTest();
        new DocumentCreationHandler().CreateDocuments(new List<Project__c>{ project });
        Test.stopTest();

        List<Document__c> docs = [SELECT Name, Project__c FROM Document__c WHERE Project__c = :project.Id WITH SYSTEM_MODE];
        System.assertEquals(1, docs.size(), 'One Document should be created per Project category');
        System.assertEquals('Marketing', docs[0].Name);
    }

    @isTest
    static void createsProjectDocumentWhenNoCategories() {
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        delete [SELECT Id FROM Document_category__c WITH SYSTEM_MODE];
        Project__c project = new Project__c(Name = 'Harbour View');
        insert project;

        Test.startTest();
        new DocumentCreationHandler().CreateDocuments(new List<Project__c>{ project });
        Test.stopTest();

        List<Document__c> docs = [SELECT Name FROM Document__c WHERE Project__c = :project.Id WITH SYSTEM_MODE];
        System.assertEquals(1, docs.size(), 'Without categories the project gets a single document');
        System.assertEquals('Harbour View', docs[0].Name);
    }

    @isTest
    static void emptyListQueuesNothing() {
        Test.startTest();
        ProjectTriggerHandler.handleAfterInsert(new List<Project__c>());
        Integer queuedJobs = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, queuedJobs, 'No job should be queued when there are no projects');
    }
}