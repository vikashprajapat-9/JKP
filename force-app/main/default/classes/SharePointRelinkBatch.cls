// Gives Sub Documents whose SharePoint link still needs a Microsoft sign-in (an organisation link, Public Link off) an
// "Anyone" view link once the site allows such links, so partners and customers can open the files on the portals.
// A file SharePoint still refuses an Anyone link for keeps its link; run the job again later.
// Start: SharePointRelinkBatch.run()
public without sharing class SharePointRelinkBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    // Each file takes two callouts (find the file behind its link, then ask for the Anyone link)
    public static final Integer BATCH_SIZE = 25;
    // Callouts of one batch end within this time of its start (the platform allows 120 seconds of callouts in all); a
    // file is only started while at least START_BEFORE_END_MS is left, and files left over keep their link until the next run
    private static final Long CALLOUT_WINDOW_MS = 110000;
    private static final Long START_BEFORE_END_MS = 25000;

    @TestVisible private Integer relinked = 0;
    @TestVisible private Integer refused = 0;
    @TestVisible private Integer failed = 0;
    @TestVisible private Integer leftOver = 0;

    public class RelinkException extends Exception {}

    // A view link SharePoint made for a file
    public class Link {
        public String url;
        public Boolean isPublic;
    }

    public static Id run() {
        return Database.executeBatch(new SharePointRelinkBatch(), BATCH_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            'SELECT Id, File_URL__c FROM Sub_Document__c WHERE Public_Link__c = false AND File_URL__c != null ORDER BY CreatedDate, Id',
            AccessLevel.SYSTEM_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<Sub_Document__c> scope) {
        Long deadline = System.currentTimeMillis() + CALLOUT_WINDOW_MS;
        List<Sub_Document__c> changes = new List<Sub_Document__c>();
        for (Sub_Document__c sub : scope) {
            // Only links on the SharePoint host are SharePoint files; any other web link is left alone
            if (!SharePointDocumentManagerController.isDriveUrl(sub.File_URL__c)) {
                continue;
            }
            // Two callouts per file, and one to spare
            if (deadline - System.currentTimeMillis() < START_BEFORE_END_MS || Limits.getCallouts() + 3 > Limits.getLimitCallouts()) {
                leftOver++;
                continue;
            }
            try {
                String itemId = itemBehind(sub.File_URL__c, deadline);
                if (itemId == null) {
                    failed++;
                    continue;
                }
                Link link = viewLink(itemId, false, deadline);
                if (link == null || link.isPublic != true) {
                    refused++;
                    continue;
                }
                changes.add(new Sub_Document__c(Id = sub.Id, File_URL__c = link.url, Public_Link__c = true));
            } catch (Exception e) {
                failed++;
                System.debug(LoggingLevel.WARN, 'Sub Document ' + sub.Id + ' keeps its link: ' + e.getMessage());
            }
        }
        // Callouts are done; the records are saved last
        Integer index = 0;
        for (Database.SaveResult result : Database.update(changes, false, AccessLevel.SYSTEM_MODE)) {
            if (result.isSuccess()) {
                relinked++;
            } else {
                failed++;
                System.debug(LoggingLevel.WARN, 'Sub Document ' + changes[index].Id + ' not saved: ' + result.getErrors()[0].getMessage());
            }
            index++;
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'SharePoint links: ' + relinked + ' now open without sign-in, ' + refused
            + ' still need a sign-in (Anyone links not allowed), ' + failed + ' not changed because of an error, '
            + leftOver + ' left for the next run.');
    }

    // The id of the file behind a SharePoint link, or null when SharePoint has no file there (anymore)
    @TestVisible
    private static String itemBehind(String fileUrl, Long deadline) {
        HttpRequest req = SharePointService.request('GET', SharePointService.sharesUrl() + SharePointDocumentManagerController.shareId(fileUrl) + '/driveItem?$select=id,file');
        req.setTimeout(timeoutUntil(deadline));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 404) {
            return null;
        }
        if (res.getStatusCode() != 200) {
            throw graphError('Could not find the file behind the link', res);
        }
        Map<String, Object> item = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return item.get('file') == null ? null : (String) item.get('id');
    }

    // A view link for a file: "Anyone with the link" when SharePoint allows it. When it refuses (400/403) the answer is
    // null, or an organisation link if organizationFallback is set. Throttling or outages throw, so the file can be
    // tried again and still get its Anyone link. Every callout ends by the deadline (System.currentTimeMillis()).
    public static Link viewLink(String itemId, Boolean organizationFallback, Long deadline) {
        String encodedId = EncodingUtil.urlEncode(itemId, 'UTF-8');
        HttpResponse res = createLink(encodedId, 'anonymous', deadline);
        if (res.getStatusCode() == 400 || res.getStatusCode() == 403) {
            if (organizationFallback != true) {
                return null;
            }
            res = createLink(encodedId, 'organization', deadline);
        }
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw graphError('Could not create a view link', res);
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> link = body.get('link') instanceof Map<String, Object> ? (Map<String, Object>) body.get('link') : null;
        if (link == null || String.isBlank((String) link.get('webUrl'))) {
            throw new RelinkException('SharePoint gave no view link');
        }
        Link result = new Link();
        result.url = (String) link.get('webUrl');
        result.isPublic = 'anonymous'.equals((String) link.get('scope'));
        return result;
    }

    public static Link viewLink(String itemId, Boolean organizationFallback) {
        return viewLink(itemId, organizationFallback, System.currentTimeMillis() + 115000);
    }

    private static HttpResponse createLink(String encodedId, String linkScope, Long deadline) {
        HttpRequest req = SharePointService.request('POST', SharePointService.itemsUrl() + encodedId + '/createLink');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'type' => 'view', 'scope' => linkScope }));
        req.setTimeout(timeoutUntil(deadline));
        return new Http().send(req);
    }

    // Timeout for a callout that must end by the deadline: at most 60 seconds, at least 1
    public static Integer timeoutUntil(Long deadline) {
        Long left = deadline - System.currentTimeMillis();
        return Math.max(1000L, Math.min(60000L, left)).intValue();
    }

    // "Could not ... (HTTP 403: accessDenied)": the status and Graph's error code only, never the answer itself
    public static RelinkException graphError(String message, HttpResponse res) {
        String code = '';
        try {
            Map<String, Object> err = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('error');
            code = err != null && err.get('code') != null ? ': ' + err.get('code') : '';
        } catch (Exception e) {
            code = '';
        }
        return new RelinkException(message + ' (HTTP ' + res.getStatusCode() + code + ')');
    }
}