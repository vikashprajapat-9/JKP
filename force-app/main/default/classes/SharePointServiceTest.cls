@isTest
private class SharePointServiceTest {

    // Answers the site's library lookup with one fixed answer, and remembers each request
    private class GraphMock implements HttpCalloutMock {
        Integer status;
        String body;
        List<HttpRequest> requests = new List<HttpRequest>();

        GraphMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            requests.add(req);
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    private static GraphMock mock(Integer status, String body) {
        GraphMock graph = new GraphMock(status, body);
        Test.setMock(HttpCalloutMock.class, graph);
        return graph;
    }

    // A site of the tests' own, so they never depend on the org's setting
    private static void useSite(String siteUrl, String siteId, String driveId) {
        SharePointService.settingRecord = new SharePoint_Setting__mdt(Credential__c = 'Test_Graph',
            Site_Url__c = siteUrl, Site_Id__c = siteId, Drive_Id__c = driveId, Host__c = 'contoso.sharepoint.com', Max_Upload_MB__c = 50);
    }

    @isTest
    static void sendsEveryRequestThroughTheNamedCredential() {
        useSite('https://contoso.sharepoint.com/sites/Data', null, 'b!library');

        HttpRequest req = SharePointService.request('POST', SharePointService.rootChildrenUrl());

        System.assertEquals('POST', req.getMethod());
        System.assertEquals('callout:Test_Graph/v1.0/drives/b!library/root/children', req.getEndpoint());
        System.assertEquals(null, req.getHeader('Authorization'), 'The Named Credential adds the sign-in');
        System.assertEquals('application/json', req.getHeader('Content-Type'));
        System.assertEquals('callout:Test_Graph/v1.0/shares/', SharePointService.sharesUrl());
        System.assertEquals('callout:Test_Graph/v1.0/$batch', SharePointService.batchUrl());
    }

    @isTest
    static void refusesASettingWithoutANamedCredential() {
        useSite('https://contoso.sharepoint.com/sites/Data', null, 'b!library');
        SharePointService.settingRecord.Credential__c = ' ';
        String message;

        try {
            SharePointService.itemsUrl();
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }

        System.assertEquals('SharePoint is not set up: the SharePoint Setting needs its Named Credential.', message);
    }

    @isTest
    static void givesBatchAddressesAndFollowsGraphsLinksThroughTheNamedCredential() {
        useSite('https://contoso.sharepoint.com/sites/Data', null, 'b!library');

        System.assertEquals('/drives/b!library/items/F1/children',
            SharePointService.relativeUrl(SharePointService.itemsUrl() + 'F1/children'));
        System.assertEquals('callout:Test_Graph/v1.0/drives/b!library/items/F1/children?$skiptoken=2',
            SharePointService.followLink('https://graph.microsoft.com/v1.0/drives/b!library/items/F1/children?$skiptoken=2'));
        System.assertEquals('https://contoso.sharepoint.com/upload', SharePointService.followLink('https://contoso.sharepoint.com/upload'),
            'Only Graph\'s own links are rewritten');
        System.assertEquals(null, SharePointService.followLink(null));
    }

    @isTest
    static void findsTheSitesDefaultLibraryOncePerTransaction() {
        useSite('https://contoso.sharepoint.com/sites/Data Hub/', null, null);
        GraphMock graph = mock(200, '{"id":"b!default-library"}');

        Test.startTest();
        String base = SharePointService.driveBaseUrl();
        String items = SharePointService.itemsUrl();
        String root = SharePointService.rootChildrenUrl();
        Test.stopTest();

        System.assertEquals('callout:Test_Graph/v1.0/drives/b!default-library', base);
        System.assertEquals(base + '/items/', items);
        System.assertEquals(base + '/root/children', root);
        System.assertEquals(1, graph.requests.size(), 'Looked up once');
        System.assertEquals('GET', graph.requests[0].getMethod());
        System.assertEquals('callout:Test_Graph/v1.0/sites/contoso.sharepoint.com:/sites/Data%20Hub:/drive?$select=id',
            graph.requests[0].getEndpoint(), 'The site by its path; the closing ":" ends the path');
    }

    @isTest
    static void usesTheSiteIdWhenSet() {
        useSite('https://contoso.sharepoint.com/sites/Data', 'contoso.sharepoint.com,1111,2222', null);
        GraphMock graph = mock(200, '{"id":"b!site-library"}');

        Test.startTest();
        String base = SharePointService.driveBaseUrl();
        Test.stopTest();

        System.assertEquals('callout:Test_Graph/v1.0/drives/b!site-library', base);
        System.assertEquals('callout:Test_Graph/v1.0/sites/contoso.sharepoint.com,1111,2222/drive?$select=id',
            graph.requests[0].getEndpoint());
    }

    @isTest
    static void usesTheConfiguredLibraryWithoutALookup() {
        useSite('https://contoso.sharepoint.com/sites/Data', null, ' b!configured ');
        GraphMock graph = mock(500, '{}');

        Test.startTest();
        String base = SharePointService.driveBaseUrl();
        Test.stopTest();

        System.assertEquals('callout:Test_Graph/v1.0/drives/b!configured', base);
        System.assertEquals(0, graph.requests.size());
    }

    @isTest
    static void theTestLibraryStandsInForTheLookup() {
        useSite('https://contoso.sharepoint.com/sites/Data', null, null);
        SharePointService.testDriveId = 'DRIVE-T';
        GraphMock graph = mock(500, '{}');

        Test.startTest();
        String base = SharePointService.driveBaseUrl();
        Test.stopTest();

        System.assertEquals('callout:Test_Graph/v1.0/drives/DRIVE-T', base);
        System.assertEquals(0, graph.requests.size(), 'The site is not called');
    }

    @isTest
    static void explainsWhenTheLibraryCannotBeOpened() {
        useSite('https://contoso.sharepoint.com/sites/Data', null, null);
        mock(403, '{"error":{"code":"accessDenied","message":"Access denied"}}');
        String denied;
        String noSite;

        Test.startTest();
        try {
            SharePointService.driveBaseUrl();
        } catch (AuraHandledException e) {
            denied = e.getMessage();
        }
        useSite(' ', null, null);
        try {
            SharePointService.driveBaseUrl();
        } catch (AuraHandledException e) {
            noSite = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals('Could not open the SharePoint document library (HTTP 403: accessDenied)', denied);
        System.assert(noSite != null && noSite.contains('needs its Site URL or Site ID'), noSite);
    }

    @isTest
    static void readsTheHostAndTheUploadLimitFromTheSetting() {
        useSite('https://contoso.sharepoint.com/sites/Data', null, null);

        System.assertEquals('contoso.sharepoint.com', SharePointService.host());
        System.assertEquals(50L * 1048576, SharePointService.maxUploadBytes());
        SharePointService.settingRecord = new SharePoint_Setting__mdt(Host__c = 'contoso.sharepoint.com');
        System.assertEquals(200L * 1048576, SharePointService.maxUploadBytes(), 'The 200 MB the upload screens have always accepted');
    }

    // A sharing link becomes SharePoint's download page for it, without its ?query or #part, read from the link alone
    @isTest
    static void turnsSharingLinksIntoTheirDirectFormWithoutCallingSharePoint() {
        String downloadPage = 'https://keells.sharepoint.com/sites/JKPConnectDataHub/_layouts/15/download.aspx?share=';

        System.assertEquals(downloadPage + 'EYaB3k-R_x9',
            SharePointService.directUrl('https://keells.sharepoint.com/:i:/s/JKPConnectDataHub/EYaB3k-R_x9?e=Ab12Cd'), 'A photo');
        System.assertEquals(downloadPage + 'EVideo', SharePointService.directUrl('https://keells.sharepoint.com/:v:/s/JKPConnectDataHub/EVideo'), 'A video');
        System.assertEquals(downloadPage + 'EPdf', SharePointService.directUrl(' https://keells.sharepoint.com/:b:/s/JKPConnectDataHub/EPdf#top '), 'A document');
        System.assertEquals('https://keells.sharepoint.com/teams/Sales/_layouts/15/download.aspx?share=ETeam',
            SharePointService.directUrl('https://keells.sharepoint.com/:x:/t/Sales/ETeam?e=1'), 'A team site');
        System.assertEquals('https://keells-my.sharepoint.com/personal/nazir_keells_com/_layouts/15/download.aspx?share=EOwn',
            SharePointService.directUrl('https://keells-my.sharepoint.com/:i:/g/personal/nazir_keells_com/EOwn?e=x'), 'A OneDrive');
        System.assertEquals('https://Keells.SharePoint.com/sites/JKPConnectDataHub/_layouts/15/download.aspx?share=abc',
            SharePointService.directUrl('HTTPS://Keells.SharePoint.com/:I:/S/JKPConnectDataHub/abc'), 'In any letter case');
        System.assertEquals(0, Limits.getCallouts(), 'SharePoint is not called');
        System.assertEquals(0, Limits.getQueries(), 'Not even the setting is read');
    }

    // Web images, links already in the direct form and anything that is not a sharing link stay as they are
    @isTest
    static void leavesEveryOtherLinkAsItIs() {
        List<String> others = new List<String>{
            'https://images.unsplash.com/photo-1?w=800',
            'https://keells.sharepoint.com/sites/JKPConnectDataHub/_layouts/15/download.aspx?share=abc',
            'https://keells.sharepoint.com/:i:/r/sites/JKPConnectDataHub/Shared%20Documents/a.jpg?csf=1&web=1',
            'https://keells.sharepoint.com/:i:/s/JKPConnectDataHub/Sub/abc',
            'https://keells.sharepoint.com.example.com/:i:/s/Site/abc',
            'https://example.com/:i:/s/Site/abc',
            'http://keells.sharepoint.com/:i:/s/Site/abc'
        };
        for (String link : others) {
            System.assertEquals(link, SharePointService.directUrl(link), link);
        }
        System.assertEquals(null, SharePointService.directUrl(null));
        System.assertEquals(null, SharePointService.directUrl(''));
        System.assertEquals(null, SharePointService.directUrl('   '));
    }

    @isTest
    static void readsTheOrgsDefaultSetting() {
        SharePoint_Setting__mdt setting = SharePointService.setting();

        System.assertEquals('Default', setting.DeveloperName);
        System.assert(SharePointService.graphUrl().startsWith('callout:'), 'Graph through the Named Credential');
        System.assert(String.isNotBlank(SharePointService.host()), 'The host whose links are trusted');
        System.assert(SharePointService.maxUploadBytes() > 0);
    }
}