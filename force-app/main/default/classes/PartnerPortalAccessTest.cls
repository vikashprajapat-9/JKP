@isTest
private class PartnerPortalAccessTest {

    // Answers the OneDrive token request and refuses the folder, so the folder jobs of the test projects end quietly
    private class OneDriveMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(req.getEndpoint().contains('/oauth2/') ? 200 : 503);
            res.setBody(req.getEndpoint().contains('/oauth2/') ? '{"access_token":"test-token"}' : '{"error":{"code":"serviceNotAvailable"}}');
            return res;
        }
    }

    private static List<Project__c> twoProjects() {
        Test.setMock(HttpCalloutMock.class, new OneDriveMock());
        List<Project__c> projects = new List<Project__c>{
            TestRecordDefaults.project('Given Project', true),
            TestRecordDefaults.project('Other Project', true)
        };
        insert projects;
        return projects;
    }

    @isTest
    static void aChannelHeadSeesTheirTeamInEveryProject() {
        List<Project__c> projects = twoProjects();
        User head = PartnerPortalTestUser.create();
        Id headAccountId = [SELECT Contact.AccountId FROM User WHERE Id = :head.Id].Contact.AccountId;

        PartnerPortalAccess access;
        Map<String, Object> binds = new Map<String, Object>();
        System.runAs(head) {
            access = PartnerPortalAccess.current();
        }

        System.assertEquals(headAccountId, access.accountId);
        System.assertEquals(false, access.isExecutive);
        System.assertEquals(null, access.projectIds, 'Not limited to some projects');
        System.assert(access.canSeeProject(projects[0].Id) && access.canSeeProject(projects[1].Id));
        System.assert(!access.canSeeProject(null));
        System.assert(access.leads(binds).contains('Channel_Partner__r.Channel_Head__c = :accessAccountId'), 'Their executives\' leads too');
        System.assertEquals(headAccountId, binds.get('accessAccountId'));
        System.assert(!access.ownLeads(binds).contains('Channel_Head__c'));
        System.assert(access.opportunities(binds).contains('Channel_Head__c'));
        System.assert(access.visits(binds).contains('Lead__r.Channel_Partner__r.Channel_Head__c'));
        System.assertEquals('Id != null', access.projects(binds));
    }

    @isTest
    static void anExecutiveSeesOnlyTheirOwnRecordsInTheirProjects() {
        List<Project__c> projects = twoProjects();
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>{ projects[0].Id });

        PartnerPortalAccess access;
        Map<String, Object> binds = new Map<String, Object>();
        System.runAs(executive) {
            access = PartnerPortalAccess.current();
            System.assert(access === PartnerPortalAccess.current(), 'Read once per user');
        }

        System.assertEquals(true, access.isExecutive);
        System.assertEquals(new Set<Id>{ projects[0].Id }, access.projectIds);
        System.assert(access.canSeeProject(projects[0].Id), 'The project their channel head gave them');
        System.assert(!access.canSeeProject(projects[1].Id), 'Not another project');
        String leads = access.leads(binds);
        System.assert(!leads.contains('Channel_Head__c') && leads.contains('Project__c IN :accessProjectIds'), leads);
        System.assertEquals(new Set<Id>{ projects[0].Id }, binds.get('accessProjectIds'));
        System.assert(access.opportunities(binds).contains('Project__c = null'), 'A converted lead\'s opportunity may have no project');
        System.assert(access.visits(binds).contains('Lead__r.Project__c IN :accessProjectIds'));
        System.assertEquals('Id IN :accessProjectIds', access.projects(binds));
    }

    @isTest
    static void anExecutiveWithoutProjectsSeesNone() {
        List<Project__c> projects = twoProjects();
        User executive = PartnerPortalTestUser.createExecutive(new List<Id>());

        PartnerPortalAccess access;
        System.runAs(executive) {
            access = PartnerPortalAccess.current();
        }

        System.assertEquals(new Set<Id>(), access.projectIds);
        System.assert(!access.canSeeProject(projects[0].Id));
    }

    @isTest
    static void aUserWithoutAPartnerAccountHasNone() {
        PartnerPortalAccess access = PartnerPortalAccess.current();

        System.assertEquals(null, access.accountId);
        System.assertEquals(false, access.isExecutive);
        System.assertEquals(null, access.projectIds);
    }
}