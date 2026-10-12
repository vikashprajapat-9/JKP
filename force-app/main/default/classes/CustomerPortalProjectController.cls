// The Projects page of the Customer Portal: every active project with its photos, one project's page and its file
// previews, read from Salesforce and OneDrive exactly as on the Partner Portal (partnerWebPortalMarketingController).
// Without sharing, because customers have no record access to projects or their files: Active__c decides what is
// shown, to any logged-in user who may call this class. Guests get nothing.
public without sharing class CustomerPortalProjectController {

    // Active projects with the photos of their "Project Images" folder
    @AuraEnabled
    public static List<partnerWebPortalMarketingController.ProjectCard> getProjects() {
        requireLogin();
        return partnerWebPortalMarketingController.cardsFor([
            SELECT Id, Name, Project_Location__c
            FROM Project__c
            WHERE Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 50
        ]);
    }

    // The whole page of an active project: photos, amenities, configurations with their price sheets, documents
    @AuraEnabled
    public static partnerWebPortalMarketingController.ProjectDetail getProjectDetails(Id projectId) {
        requireLogin();
        return partnerWebPortalMarketingController.detailsOf(projectId);
    }

    // Short-lived embeddable preview of a file the project page shows: a photo, a project document or a price sheet of
    // an active project. Files of the Marketing folder are for partners only.
    @AuraEnabled
    public static String getFilePreviewUrl(Id subDocumentId) {
        requireLogin();
        Sub_Document__c file = partnerWebPortalMarketingController.portalFile(subDocumentId);
        if (file == null || !partnerWebPortalMarketingController.isProjectPageFile(file)) {
            throw userError(Label.Customer_Portal_File_Not_Available);
        }
        return partnerWebPortalMarketingController.previewUrlOf(file);
    }

    private static void requireLogin() {
        if (isGuest()) {
            throw userError(Label.Customer_Portal_Login_Required);
        }
    }

    // Tests set this to act as a guest or as a logged-in user
    @TestVisible
    private static Boolean guestOverride;

    private static Boolean isGuest() {
        return guestOverride != null ? guestOverride : UserInfo.getUserType() == 'Guest';
    }

    // AuraHandledException only exposes its text to Apex callers (and tests) when setMessage is also called
    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}