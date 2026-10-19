// Microsoft Graph access to the client's SharePoint site through the Named Credential named in the setting
// (SharePoint_Graph). Its External Credential signs in as the client's own Azure app (client credentials, app-only) and
// adds the token to every call, so no secret or token is ever handled here. Users reach it through their profile
// (External Credential Principal Access). The app may use that one site only (Sites.Selected), so every address here
// stays inside it: the site, its document library (/drives/<library id>/...), /shares/ links and upload-session URLs.
// Nothing calls /users or /me. SharePoint_Setting__mdt "Default" holds the Named Credential, site, library, host and
// upload limit. directUrl gives the address a page or app shows a file from; it is read from the file's link alone,
// so showing or opening a file never calls SharePoint.
public without sharing class SharePointService {

    // Graph's own address, as it appears in the links Graph returns (@odata.nextLink)
    private static final String GRAPH_ADDRESS = 'https://graph.microsoft.com/v1.0';
    // A sharing link as SharePoint writes it: https://<tenant>.sharepoint.com/:<letter>:/s/<site>/<token> (/t/ for a
    // team site) or /:<letter>:/g/personal/<user>/<token> (someone's OneDrive), maybe followed by a ?query or #part.
    // Its parts: 1 host, 2 s or t, 3 site, 4 OneDrive user, 5 token.
    private static final Pattern SHARING_LINK = Pattern.compile(
        '(?i)https://([a-z0-9-]+(?:\\.[a-z0-9-]+)*\\.sharepoint\\.com)/:[a-z]:/(?:([st])/([^/?#]+)|g/personal/([^/?#]+))/([^/?#]+)(?:[?#].*)?'
    );
    private static final Long BYTES_PER_MB = 1048576;
    // Upload limit when the setting leaves it blank: the 200 MB the upload screens have always accepted
    private static final Long DEFAULT_MAX_UPLOAD_MB = 200;

    // When set, driveBaseUrl() uses it, so tests never look up the library
    @TestVisible static String testDriveId;

    // Read once per transaction; tests may put in a record of their own
    @TestVisible private static SharePoint_Setting__mdt settingRecord;
    private static String driveId;

    // SharePoint_Setting__mdt "Default"
    public static SharePoint_Setting__mdt setting() {
        if (settingRecord == null) {
            List<SharePoint_Setting__mdt> records = [
                SELECT DeveloperName, Credential__c, Site_Url__c, Site_Id__c, Drive_Id__c, Host__c, Max_Upload_MB__c
                FROM SharePoint_Setting__mdt
                WHERE DeveloperName = 'Default'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (records.isEmpty()) {
                throw userError('SharePoint is not set up: the SharePoint Setting "Default" was not found.');
            }
            settingRecord = records[0];
        }
        return settingRecord;
    }

    // callout:<Named Credential>/v1.0, the root every Graph address starts from
    public static String graphUrl() {
        String name = setting().Credential__c == null ? '' : setting().Credential__c.trim();
        if (String.isBlank(name)) {
            throw userError('SharePoint is not set up: the SharePoint Setting needs its Named Credential.');
        }
        return 'callout:' + name + '/v1.0';
    }

    // <Graph>/drives/<library id>: the library in the setting, else the site's default library (Documents), looked up
    // once per transaction
    public static String driveBaseUrl() {
        if (testDriveId != null) {
            return graphUrl() + '/drives/' + testDriveId;
        }
        if (driveId == null) {
            String configured = setting().Drive_Id__c;
            driveId = String.isNotBlank(configured) ? configured.trim() : defaultLibraryId();
        }
        return graphUrl() + '/drives/' + driveId;
    }

    private static String defaultLibraryId() {
        HttpResponse res = new Http().send(request('GET', graphUrl() + '/sites/' + siteAddress() + '/drive?$select=id'));
        String id;
        if (res.getStatusCode() == 200) {
            id = (String) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('id');
        }
        if (String.isBlank(id)) {
            throw graphError('Could not open the SharePoint document library', res);
        }
        return id;
    }

    // The site as Graph addresses it: the Site ID when set, else "<host>:/<site path>:" from the Site URL, for example
    // keells.sharepoint.com:/sites/JKPConnectDataHub: (the closing ":" ends the path, so "/drive" can follow)
    private static String siteAddress() {
        SharePoint_Setting__mdt config = setting();
        if (String.isNotBlank(config.Site_Id__c)) {
            return config.Site_Id__c.trim();
        }
        String address = (config.Site_Url__c == null ? '' : config.Site_Url__c.trim())
            .removeStartIgnoreCase('https://').removeStartIgnoreCase('http://');
        String siteHost = address.substringBefore('/');
        List<String> segments = new List<String>();
        String path = address.contains('/') ? address.substringAfter('/').substringBefore('?').substringBefore('#') : '';
        for (String segment : path.split('/')) {
            if (String.isNotBlank(segment)) {
                segments.add(EncodingUtil.urlEncode(EncodingUtil.urlDecode(segment, 'UTF-8'), 'UTF-8').replace('+', '%20'));
            }
        }
        if (String.isBlank(siteHost) || segments.isEmpty()) {
            throw userError('SharePoint is not set up: the SharePoint Setting needs its Site URL or Site ID.');
        }
        return siteHost + ':/' + String.join(segments, '/') + ':';
    }

    // Folder and file addresses: itemsUrl() + item id (+ '/children', ':/<name>:/createUploadSession', ...)
    public static String itemsUrl() {
        return driveBaseUrl() + '/items/';
    }

    // Where folders at the top of the library are created
    public static String rootChildrenUrl() {
        return driveBaseUrl() + '/root/children';
    }

    // Share links as Graph reads them: sharesUrl() + share id + '/driveItem'
    public static String sharesUrl() {
        return graphUrl() + '/shares/';
    }

    // Several Graph requests in one call; each inner request takes its address from relativeUrl()
    public static String batchUrl() {
        return graphUrl() + '/$batch';
    }

    // An address without the Graph root, as $batch wants it: /drives/<id>/items/<folder>/children
    public static String relativeUrl(String address) {
        return address == null ? null : address.removeStart(graphUrl());
    }

    // A link Graph returned (the next page of a folder) as an address that goes through the Named Credential again
    public static String followLink(String link) {
        if (String.isBlank(link) || !link.startsWithIgnoreCase(GRAPH_ADDRESS)) {
            return link;
        }
        return graphUrl() + link.substring(GRAPH_ADDRESS.length());
    }

    // The host SharePoint gives links and upload sessions on (keells.sharepoint.com); only URLs on it are trusted
    public static String host() {
        String configured = setting().Host__c;
        return configured == null ? '' : configured.trim();
    }

    // The address a page or app shows a file from (<img>, <video>) or downloads it from: for a SharePoint sharing link,
    // SharePoint's own download page for it, https://<host>/sites/<site>/_layouts/15/download.aspx?share=<token>
    // (teams/<site> for a team site, personal/<user> for a OneDrive), without the link's ?query. It sends the file
    // itself, with no cookie and no redirect, so it works on phones and with third-party cookies blocked; SharePoint
    // sends it as a download, so a document is saved rather than shown. Any other link (a web image, a link already in
    // this form) comes back unchanged, and a blank one as null. Nothing is called or queried: only the link is read.
    public static String directUrl(String link) {
        if (String.isBlank(link)) {
            return null;
        }
        Matcher parts = SHARING_LINK.matcher(link.trim());
        if (!parts.matches()) {
            return link;
        }
        String web = parts.group(2) == null ? 'personal/' + parts.group(4)
            : (parts.group(2).equalsIgnoreCase('t') ? 'teams/' : 'sites/') + parts.group(3);
        return 'https://' + parts.group(1) + '/' + web + '/_layouts/15/download.aspx?share=' + parts.group(5);
    }

    // Largest file the upload screens accept: the setting's Max Upload Size (MB), 200 MB when it is blank
    public static Long maxUploadBytes() {
        Decimal megabytes = setting().Max_Upload_MB__c;
        return (megabytes == null || megabytes <= 0 ? DEFAULT_MAX_UPLOAD_MB : megabytes.longValue()) * BYTES_PER_MB;
    }

    // A Graph request: the Named Credential signs it in as the app; JSON body, 60 second timeout
    public static HttpRequest request(String method, String endpoint) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(endpoint);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        return req;
    }

    private static AuraHandledException graphError(String message, HttpResponse res) {
        String code = '';
        try {
            Map<String, Object> err = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('error');
            code = err != null ? ': ' + err.get('code') : '';
        } catch (Exception e) {
            code = '';
        }
        return userError(message + ' (HTTP ' + res.getStatusCode() + code + ')');
    }

    // AuraHandledException only exposes its text to Apex callers (and tests) when setMessage is also called
    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}