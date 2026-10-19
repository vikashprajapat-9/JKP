@isTest
private class SharePointRelinkBatchTest {

    // Graph as the batch calls it: share links resolve to items, and createLink answers per item
    private class GraphMock implements HttpCalloutMock {
        Map<String, String> itemByShareId = new Map<String, String>();
        Set<String> anyoneRefused = new Set<String>();
        List<String> calls = new List<String>();

        public HttpResponse respond(HttpRequest req) {
            String url = req.getEndpoint();
            calls.add(req.getMethod() + ' ' + url + ' ' + req.getBody());
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            // Every Graph call goes through the Named Credential, which adds the sign-in itself
            if (!url.startsWith('callout:SharePoint_Graph/v1.0/') || req.getHeader('Authorization') != null) {
                res.setStatusCode(400);
                res.setBody('{"error":{"code":"invalidRequest"}}');
            } else if (url.contains('/sites/') && url.contains('/drive')) {
                res.setStatusCode(200);
                res.setBody('{"id":"TEST-DRIVE"}');
            } else if (url.startsWith('callout:SharePoint_Graph/v1.0/shares/')) {
                String itemId = itemByShareId.get(url.substringAfter('/shares/').substringBefore('/driveItem'));
                res.setStatusCode(itemId == null ? 404 : 200);
                res.setBody(itemId == null ? '{"error":{"code":"itemNotFound"}}' : '{"id":"' + itemId + '","file":{}}');
            } else if (url.endsWith('/createLink')) {
                String itemId = url.substringAfter('/items/').substringBefore('/createLink');
                String scope = (String) ((Map<String, Object>) JSON.deserializeUntyped(req.getBody())).get('scope');
                if (scope == 'anonymous' && anyoneRefused.contains(itemId)) {
                    res.setStatusCode(403);
                    res.setBody('{"error":{"code":"accessDenied"}}');
                } else {
                    res.setStatusCode(201);
                    res.setBody('{"link":{"webUrl":"' + link(scope + '-' + itemId) + '","scope":"' + scope + '"}}');
                }
            } else {
                res.setStatusCode(404);
                res.setBody('{"error":{"code":"itemNotFound"}}');
            }
            return res;
        }
    }

    private static String link(String key) {
        return 'https://' + SharePointService.host() + '/:b:/s/JKPConnectDataHub/' + key;
    }

    @testSetup
    static void setup() {
        Document__c folder = new Document__c(Name = 'Marketing', Document_Id__c = 'FOLDER-1');
        insert folder;
        insert new List<Sub_Document__c>{
            new Sub_Document__c(Name = 'brochure.pdf', Document__c = folder.Id, File_URL__c = link('org-brochure')),
            new Sub_Document__c(Name = 'plan.pdf', Document__c = folder.Id, File_URL__c = link('org-plan')),
            new Sub_Document__c(Name = 'gone.pdf', Document__c = folder.Id, File_URL__c = link('org-gone')),
            new Sub_Document__c(Name = 'photo.jpg', Document__c = folder.Id, File_URL__c = 'https://images.example.com/photo.jpg'),
            new Sub_Document__c(Name = 'open.pdf', Document__c = folder.Id, File_URL__c = link('anyone-open'), Public_Link__c = true)
        };
    }

    // brochure.pdf may get an Anyone link, plan.pdf is still refused one, gone.pdf is no longer in SharePoint
    private static GraphMock mockGraph() {
        SharePointService.testDriveId = 'TEST-DRIVE';
        GraphMock mock = new GraphMock();
        mock.itemByShareId.put(SharePointDocumentManagerController.shareId(link('org-brochure')), 'ITEM-BROCHURE');
        mock.itemByShareId.put(SharePointDocumentManagerController.shareId(link('org-plan')), 'ITEM-PLAN');
        mock.anyoneRefused.add('ITEM-PLAN');
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    private static Sub_Document__c file(String name) {
        return [SELECT Id, File_URL__c, Public_Link__c FROM Sub_Document__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1];
    }

    @isTest
    static void givesOrganisationLinksAnAnyoneLinkOnceAllowed() {
        GraphMock mock = mockGraph();
        List<Sub_Document__c> scope = [
            SELECT Id, File_URL__c FROM Sub_Document__c WHERE Public_Link__c = false AND File_URL__c != null WITH SYSTEM_MODE
        ];
        SharePointRelinkBatch batch = new SharePointRelinkBatch();

        Test.startTest();
        batch.execute(null, scope);
        Test.stopTest();

        Sub_Document__c brochure = file('brochure.pdf');
        System.assertEquals(link('anonymous-ITEM-BROCHURE'), brochure.File_URL__c);
        System.assertEquals(true, brochure.Public_Link__c);
        Sub_Document__c plan = file('plan.pdf');
        System.assertEquals(link('org-plan'), plan.File_URL__c, 'Still refused: the link stays');
        System.assertEquals(false, plan.Public_Link__c);
        System.assertEquals(link('org-gone'), file('gone.pdf').File_URL__c);
        System.assertEquals('https://images.example.com/photo.jpg', file('photo.jpg').File_URL__c);
        System.assertEquals(1, batch.relinked);
        System.assertEquals(1, batch.refused);
        System.assertEquals(1, batch.failed);
        for (String call : mock.calls) {
            System.assert(!call.contains('images.example.com'), 'A web link is never called: ' + call);
            System.assert(!call.contains('organization'), 'The batch never asks for an organisation link');
        }
    }

    @isTest
    static void runsAsABatch() {
        mockGraph();

        Test.startTest();
        Id jobId = SharePointRelinkBatch.run();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(1, [SELECT COUNT() FROM AsyncApexJob WHERE Id = :jobId AND Status = 'Completed']);
    }

    @isTest
    static void viewLinkFallsBackToAnOrganisationLinkWhenAsked() {
        GraphMock mock = mockGraph();
        mock.anyoneRefused.add('ITEM-X');

        Test.startTest();
        SharePointRelinkBatch.Link refused = SharePointRelinkBatch.viewLink('ITEM-X', false);
        SharePointRelinkBatch.Link organisation = SharePointRelinkBatch.viewLink('ITEM-X', true);
        SharePointRelinkBatch.Link anyone = SharePointRelinkBatch.viewLink('ITEM-Y', true);
        Test.stopTest();

        System.assertEquals(null, refused);
        System.assertEquals(link('organization-ITEM-X'), organisation.url);
        System.assertEquals(false, organisation.isPublic);
        System.assertEquals(link('anonymous-ITEM-Y'), anyone.url);
        System.assertEquals(true, anyone.isPublic);
    }

    @isTest
    static void timeoutsStayWithinTheDeadline() {
        Long now = System.currentTimeMillis();
        System.assertEquals(60000, SharePointRelinkBatch.timeoutUntil(now + 300000));
        System.assert(SharePointRelinkBatch.timeoutUntil(now + 20000) <= 20000);
        System.assertEquals(1000, SharePointRelinkBatch.timeoutUntil(now - 5000));
    }
}