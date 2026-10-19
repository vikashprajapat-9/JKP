// The My Contract page of the partner portal: the exclusive agent contract John Keells Properties prepares for a partner
// who met the conditions of their temporary access (PartnerContractService). The partner follows it from preparation to
// completion and signs it offline: once JKP has verified a draft (Sent for Signature) they download it here, sign it on
// paper and hand the signed copy to their CP Executive, who records it (Signed) and adds the scan with the contract
// dates (Completed). The signed scan can then be downloaded here too. The files are in SharePoint, in the contract's
// Contract Generated Document and Signed Document folders (ContractDocumentService): the page gets the direct form of
// the file's Sub Document link to save it from (SharePointService.directUrl), so SharePoint is not called; contracts
// made before keep theirs in Salesforce Files, sent as their contents.
// Only a channel head has a contract: an executive's channel partner holds it, and a user without a partner account (an
// internal user previewing the site) has none (PartnerPortalAccess). Partners cannot see contracts or their files, so
// this runs without sharing and in system mode, and every query is limited to the logged-in partner's own account.
public without sharing class partnerWebPortalContractController {
    // Messages this class shows or sends
    @TestVisible private static final String PARTNER_PORTAL_CONTRACT_COMPLETED = 'Your signed contract is on record with John Keells Properties.';
    @TestVisible private static final String PARTNER_PORTAL_CONTRACT_EXECUTIVE = 'Your channel partner holds the contract with John Keells Properties.';
    @TestVisible private static final String PARTNER_PORTAL_CONTRACT_NONE = 'No contract yet. When you meet the conditions of your temporary access, John Keells Properties prepares your exclusive partner contract here.';
    @TestVisible private static final String PARTNER_PORTAL_CONTRACT_PREPARING = 'Your exclusive partner contract is being prepared and verified by John Keells Properties. You will receive an email when it is ready to sign.';
    @TestVisible private static final String PARTNER_PORTAL_CONTRACT_READY = 'Your contract is ready. Download it, print it and sign it, then hand the signed copy to your JKP CP Executive.';
    @TestVisible private static final String PARTNER_PORTAL_CONTRACT_SIGNED = 'Thank you for signing. You are now an Exclusive channel partner of John Keells Properties. Your CP Executive is recording the signed contract.';


    private static final String DRAFT_FILE = 'draft';
    private static final String SIGNED_FILE = 'signed';
    private static final String DATE_FORMAT = 'dd MMM yyyy';
    private static final String DEFAULT_FILE_NAME = 'Contract';
    private static final String DEFAULT_MIME_TYPE = 'application/octet-stream';
    // Characters a file name cannot have on Windows or macOS
    private static final String UNSAFE_FILE_NAME_CHARACTERS = '[\\\\/:*?"<>|]';

    // The type of the file the browser saves, by ContentVersion FileType or file extension: the PDF of a draft, or the
    // signed copy as a PDF, a scan or a photo
    private static final Map<String, String> MIME_TYPES = new Map<String, String>{
        'PDF' => 'application/pdf',
        'JPG' => 'image/jpeg',
        'JPEG' => 'image/jpeg',
        'PNG' => 'image/png',
        'GIF' => 'image/gif',
        'TIF' => 'image/tiff',
        'TIFF' => 'image/tiff',
        'WORD' => 'application/msword',
        'DOC' => 'application/msword',
        'WORD_X' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'DOCX' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    };

    // The page's step for each Contract Stage. Not Signed goes straight back to Draft with the next version, so it is
    // being prepared as well.
    private static final Integer STEP_PREPARING = 1;
    private static final Integer STEP_READY = 2;
    private static final Integer STEP_SIGNED = 3;
    private static final Integer STEP_COMPLETED = 4;
    private static final Map<String, Integer> STEP_BY_STAGE = new Map<String, Integer>{
        PartnerContractService.DRAFT => STEP_PREPARING,
        PartnerContractService.NOT_SIGNED => STEP_PREPARING,
        PartnerContractService.SENT => STEP_READY,
        PartnerContractService.SIGNED => STEP_SIGNED,
        PartnerContractService.COMPLETED => STEP_COMPLETED
    };

    @TestVisible
    private static final String LOAD_ERROR = 'Your contract could not be loaded right now. Please try again.';
    @TestVisible
    private static final String DOWNLOAD_ERROR = 'The contract could not be downloaded right now. Please try again.';
    @TestVisible
    private static final String UNKNOWN_FILE = 'Choose the contract or the signed contract to download.';
    @TestVisible
    private static final String NOT_A_PARTNER = 'Only channel partners have a contract here.';
    @TestVisible
    private static final String DRAFT_NOT_READY = 'Your contract can be downloaded once John Keells Properties has verified it. '
        + 'You will receive an email when it is ready to sign.';
    @TestVisible
    private static final String SIGNED_NOT_READY = 'Your signed contract can be downloaded once your JKP CP Executive has recorded it.';
    @TestVisible
    private static final String FILE_NOT_FOUND = 'The contract file could not be found. Please ask your JKP CP Executive for a copy.';
    @TestVisible
    private static final String FILE_TOO_LARGE = 'This file is too large to download here. Please ask your JKP CP Executive for a copy.';

    // Larger files are refused: they travel to the page as text, within the limits of one request; tests set their own
    @TestVisible
    private static Integer maxFileBytes = 3 * 1024 * 1024;

    // What the page shows.
    // - available: whether the logged-in user has a contract here at all; not for an executive or a user without a
    //   partner account, whose message says why.
    // - step: 0 without a contract, 1 being prepared (Draft, Not Signed), 2 Sent for Signature, 3 Signed, 4 Completed;
    //   stage is the Contract Stage itself.
    // - Dates are formatted for the page ("05 Oct 2026"), or null.
    // - canDownloadDraft: the draft, once JKP has verified it (never while it is being prepared); canDownloadSigned: the
    //   signed scan, once the contract is Completed.
    public class ContractView {
        @AuraEnabled public Boolean available = false;
        @AuraEnabled public Boolean isExecutive = false;
        @AuraEnabled public Boolean hasContract = false;
        @AuraEnabled public String contractNumber;
        @AuraEnabled public String stage;
        @AuraEnabled public Integer step = 0;
        @AuraEnabled public String message;
        @AuraEnabled public Integer draftVersion;
        @AuraEnabled public Integer termMonths;
        @AuraEnabled public String signedOn;
        @AuraEnabled public String contractStart;
        @AuraEnabled public String contractEnd;
        @AuraEnabled public String temporaryStart;
        @AuraEnabled public String temporaryEnd;
        @AuraEnabled public String partnerType;
        @AuraEnabled public Boolean canDownloadDraft = false;
        @AuraEnabled public Boolean canDownloadSigned = false;
    }

    // A contract file for the page to save: its name and type, and either a link to save it from (url; a file in
    // SharePoint, the direct form of its Sub Document link) or its contents (base64; a file in Salesforce Files)
    public class FileDownload {
        @AuraEnabled public String fileName;
        @AuraEnabled public String mimeType;
        @AuraEnabled public String base64;
        @AuraEnabled public String url;
    }

    // The logged-in partner's contract. Not cacheable: the page reads it again each time it opens, as the contract moves on.
    @AuraEnabled
    public static ContractView getMyContract() {
        try {
            return viewOf(PartnerPortalAccess.current());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'My Contract could not be loaded: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw userError(LOAD_ERROR);
        }
    }

    // A file of the logged-in partner's contract, by kind: 'draft', the contract to sign, or 'signed', the signed scan.
    // The same rules as the page's buttons (canDownloadDraft, canDownloadSigned); refused otherwise, with the reason.
    @AuraEnabled
    public static FileDownload getContractFile(String kind) {
        try {
            String fileKind = kind == null ? '' : kind.trim().toLowerCase();
            if (fileKind != DRAFT_FILE && fileKind != SIGNED_FILE) {
                throw userError(UNKNOWN_FILE);
            }
            PartnerPortalAccess access = PartnerPortalAccess.current();
            if (access.isExecutive) {
                throw userError(PARTNER_PORTAL_CONTRACT_EXECUTIVE);
            }
            if (access.accountId == null) {
                throw userError(NOT_A_PARTNER);
            }
            Contract latest = latestContract(access.accountId);
            if (fileKind == DRAFT_FILE) {
                if (latest == null || !canDownloadDraft(latest)) {
                    throw userError(DRAFT_NOT_READY);
                }
                return download(latest.Draft_Document_Id__c);
            }
            if (latest == null || !canDownloadSigned(latest)) {
                throw userError(SIGNED_NOT_READY);
            }
            return download(latest.Signed_Document_Id__c);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Contract file not sent: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw userError(DOWNLOAD_ERROR);
        }
    }

    // The page for this user: the partner's latest contract with their Partner Type and temporary access dates, or for
    // an executive or a user without a partner account, only why there is none
    private static ContractView viewOf(PartnerPortalAccess access) {
        ContractView view = new ContractView();
        view.isExecutive = access.isExecutive;
        if (access.accountId == null || access.isExecutive) {
            view.message = access.isExecutive ? PARTNER_PORTAL_CONTRACT_EXECUTIVE : PARTNER_PORTAL_CONTRACT_NONE;
            return view;
        }
        view.available = true;
        for (Account partner : [
            SELECT Partner_Type__c, Temporary_Access_Start_Date__c, Temporary_Access_End_Date__c
            FROM Account
            WHERE Id = :access.accountId
            WITH SYSTEM_MODE
        ]) {
            view.partnerType = partner.Partner_Type__c;
            view.temporaryStart = formatted(partner.Temporary_Access_Start_Date__c);
            view.temporaryEnd = formatted(partner.Temporary_Access_End_Date__c);
        }

        Contract latest = latestContract(access.accountId);
        if (latest == null) {
            view.message = PARTNER_PORTAL_CONTRACT_NONE;
            return view;
        }
        view.hasContract = true;
        view.contractNumber = latest.ContractNumber;
        view.stage = latest.Contract_Stage__c;
        view.step = stepOf(latest.Contract_Stage__c);
        view.message = messageOf(view.step);
        view.draftVersion = latest.Draft_Version__c == null ? null : latest.Draft_Version__c.intValue();
        view.termMonths = latest.ContractTerm;
        view.signedOn = formatted(latest.Signed_On__c);
        view.contractStart = formatted(latest.Contract_Start__c);
        view.contractEnd = formatted(latest.Contract_End__c);
        view.canDownloadDraft = canDownloadDraft(latest);
        view.canDownloadSigned = canDownloadSigned(latest);
        return view;
    }

    // The partner's latest contract. A partner has one (Not Signed drafts the same contract again); should there be
    // more, the newest is theirs now.
    private static Contract latestContract(Id accountId) {
        List<Contract> contracts = [
            SELECT Id, ContractNumber, Contract_Stage__c, Draft_Version__c, ContractTerm, Signed_On__c, Contract_Start__c,
                Contract_End__c, Draft_Document_Id__c, Signed_Document_Id__c
            FROM Contract
            WHERE AccountId = :accountId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        return contracts.isEmpty() ? null : contracts[0];
    }

    // A contract with a stage the page does not know (or none yet) is being prepared
    private static Integer stepOf(String stage) {
        Integer step = stage == null ? null : STEP_BY_STAGE.get(stage);
        return step == null ? STEP_PREPARING : step;
    }

    private static String messageOf(Integer step) {
        if (step == STEP_READY) {
            return PARTNER_PORTAL_CONTRACT_READY;
        }
        if (step == STEP_SIGNED) {
            return PARTNER_PORTAL_CONTRACT_SIGNED;
        }
        if (step == STEP_COMPLETED) {
            return PARTNER_PORTAL_CONTRACT_COMPLETED;
        }
        return PARTNER_PORTAL_CONTRACT_PREPARING;
    }

    // The draft once JKP has verified it and sent it for signature, and from then on; never while it is being prepared
    private static Boolean canDownloadDraft(Contract record) {
        return String.isNotBlank(record.Draft_Document_Id__c) && stepOf(record.Contract_Stage__c) >= STEP_READY;
    }

    // The signed scan once the contract is Completed
    private static Boolean canDownloadSigned(Contract record) {
        return String.isNotBlank(record.Signed_Document_Id__c) && stepOf(record.Contract_Stage__c) == STEP_COMPLETED;
    }

    // The file a document Id field names: a Sub Document (in SharePoint), or the latest version of a Salesforce File;
    // refused when it is gone, or too large to send as contents. Contents are read only once the size is known.
    private static FileDownload download(String documentId) {
        Sub_Document__c driveFile = subDocumentOf(documentId);
        if (driveFile != null) {
            return driveDownload(driveFile);
        }
        Id fileId = contentDocumentIdOf(documentId);
        List<ContentVersion> versions = fileId == null ? new List<ContentVersion>() : [
            SELECT Id, Title, FileExtension, FileType, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId = :fileId AND IsLatest = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw userError(FILE_NOT_FOUND);
        }
        ContentVersion version = versions[0];
        if (version.ContentSize != null && version.ContentSize > maxFileBytes) {
            throw userError(FILE_TOO_LARGE);
        }
        FileDownload file = new FileDownload();
        file.fileName = fileNameOf(version.Title, version.FileExtension);
        file.mimeType = mimeTypeOf(version.FileType, version.FileExtension);
        file.base64 = EncodingUtil.base64Encode([SELECT VersionData FROM ContentVersion WHERE Id = :version.Id WITH SYSTEM_MODE].VersionData);
        return file;
    }

    // The SharePoint file's own download link, the direct form of its Sub Document link (SharePoint sends the file as a
    // download), with the file's name and type from the Sub Document. Read from the record alone: SharePoint is not
    // called. A Sub Document without a link is not found.
    private static FileDownload driveDownload(Sub_Document__c driveFile) {
        String directLink = SharePointService.directUrl(driveFile.File_URL__c);
        if (String.isBlank(directLink)) {
            throw userError(FILE_NOT_FOUND);
        }
        String name = driveFile.Name == null ? '' : driveFile.Name.trim();
        String extension = name.contains('.') ? name.substringAfterLast('.') : null;
        FileDownload download = new FileDownload();
        download.fileName = fileNameOf(name, extension);
        download.mimeType = mimeTypeOf(null, extension);
        download.url = directLink;
        return download;
    }

    // The Sub Document a document Id field names, or null when it names none
    private static Sub_Document__c subDocumentOf(String value) {
        Id fileId;
        try {
            fileId = Id.valueOf(value.trim());
        } catch (Exception e) {
            return null;
        }
        if (fileId.getSObjectType() != Sub_Document__c.SObjectType) {
            return null;
        }
        List<Sub_Document__c> files = [SELECT Id, Name, File_URL__c FROM Sub_Document__c WHERE Id = :fileId WITH SYSTEM_MODE];
        if (files.isEmpty()) {
            throw userError(FILE_NOT_FOUND);
        }
        return files[0];
    }

    // The file (ContentDocument) a document Id field names, or null when it names none
    private static Id contentDocumentIdOf(String value) {
        try {
            Id fileId = Id.valueOf(value.trim());
            return fileId.getSObjectType() == ContentDocument.SObjectType ? fileId : null;
        } catch (Exception e) {
            return null;
        }
    }

    // The title with its extension (unless the title ends with it already), without characters a file name cannot have
    @TestVisible
    private static String fileNameOf(String title, String extension) {
        String name = String.isBlank(title) ? DEFAULT_FILE_NAME : title.trim();
        if (String.isNotBlank(extension) && !name.toLowerCase().endsWith('.' + extension.toLowerCase())) {
            name += '.' + extension;
        }
        return name.replaceAll(UNSAFE_FILE_NAME_CHARACTERS, '-');
    }

    @TestVisible
    private static String mimeTypeOf(String fileType, String extension) {
        for (String candidate : new List<String>{ fileType, extension }) {
            String key = candidate == null ? '' : candidate.trim().toUpperCase();
            if (MIME_TYPES.containsKey(key)) {
                return MIME_TYPES.get(key);
            }
        }
        return DEFAULT_MIME_TYPE;
    }

    // For example "05 Oct 2026"; null without a date. At noon, so no time zone or daylight saving change moves the day.
    private static String formatted(Date value) {
        return value == null ? null : Datetime.newInstance(value, Time.newInstance(12, 0, 0, 0)).format(DATE_FORMAT);
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}