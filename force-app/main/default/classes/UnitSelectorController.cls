public with sharing class UnitSelectorController {
    @AuraEnabled(cacheable=true)
    public static List<Company__c> getCompanies() {
        return [SELECT Id, Name FROM Company__c ORDER BY Name];
    }
    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects(Id companyId) {
        if (companyId == null) {
            return new List<Project__c>();
        }
        return [ SELECT Id, Name FROM Project__c WHERE Company__c = :companyId ORDER BY Name ];
    }
    @AuraEnabled(cacheable=true)
    public static List<Block__c> getTowers(Id projectId) {
        if (projectId == null) {
            return new List<Block__c>();
        }
        return [SELECT Id, Name FROM Block__c WHERE Project__c = :projectId ORDER BY Name ];
    }
    @AuraEnabled(cacheable=true)
    public static List<Floor__c> getFloors(Id towerId) {
        if (towerId == null) {
            return new List<Floor__c>();
        }
        return [SELECT Id, Name FROM Floor__c WHERE Block__c = :towerId ORDER BY Name ];
    }
    @AuraEnabled(cacheable=true)
    public static List<Unit__c> getUnits(Id companyId,Id projectId,Id towerId,Id floorId) {
        if (floorId != null) {
            return [SELECT Id, Name, Unit_Name_Code__c FROM Unit__c WHERE Floor__c = :floorId  AND Internal_QC__c = false ORDER BY Name];
        }
        if (towerId != null) {
            return [SELECT Id, Name, Unit_Name_Code__c FROM Unit__c WHERE Floor__r.Block__c = :towerId   AND Internal_QC__c = false ORDER BY Name];
        }
        if (projectId != null) {
            return [ SELECT Id, Name, Unit_Name_Code__c FROM Unit__c WHERE Floor__r.Block__r.Project__c = :projectId  AND Internal_QC__c = false  ORDER BY Name];
        }
        if (companyId != null) {
            return [SELECT Id, Name, Unit_Name_Code__c FROM Unit__c WHERE Floor__r.Block__r.Project__r.Company__c = :companyId  AND Internal_QC__c = false ORDER BY Name ];
        }
        return new List<Unit__c>();
    }
    @AuraEnabled
    public static void updateInternalQC(List<Id> unitIds) {
        if (unitIds == null || unitIds.isEmpty()) {
            return;
        }
        List<Unit__c> unitsToUpdate = [SELECT Id,Internal_QC__c,Name,Floor__r.Name,Floor__r.Block__r.Name, Floor__r.Block__r.Project__r.Name,  Unit_Name_Code__c FROM Unit__c WHERE Id IN :unitIds];
        List<Unit__c> unitUpdates = new List<Unit__c>();
        for (Unit__c unit : unitsToUpdate) {
           // unit.Internal_QC__c = true;
            unitUpdates.add(new Unit__c(
            Id = unit.Id,
            Internal_QC__c = true
            ));
        }
        if (!unitUpdates.isEmpty()) {
            update unitUpdates;
        }
        List<Opportunity> opportunitiesToUpdate = [SELECT Id,Name,StageName,Unit__c FROM Opportunity WHERE Unit__c IN :unitIds AND StageName = 'Tranche Payment'];
        for (Opportunity opp : opportunitiesToUpdate) {
            opp.StageName = 'Internal QC';
        }
        if (!opportunitiesToUpdate.isEmpty()) {
            update opportunitiesToUpdate;
        }
        if (opportunitiesToUpdate.isEmpty()) {
            return;
        }
        List<User> qcOwners = [SELECT Id ,Name,Email,UserRole.Name  from User WHERE UserRole.Name ='Senior Manager QA' AND IsActive = true LIMIT 1];
        if (qcOwners.isEmpty()) {
            throw new AuraHandledException(
                'Active user "Senior Manager QA" was not found.'
            );
        }
        User qcOwner = qcOwners[0];
        Map<Id, Id> unitToOpportunityMap = new Map<Id, Id>();
        for (Opportunity opp : opportunitiesToUpdate) {
            if (opp.Unit__c != null) {
                unitToOpportunityMap.put(
                    opp.Unit__c,
                    opp.Id
                );
            }
        }
        List<QC_Request__c> requestsToInsert = new List<QC_Request__c>();
        for (Unit__c unit : unitsToUpdate) {
            if (!unitToOpportunityMap.containsKey(unit.Id)) {
                continue;
            }
            QC_Request__c qc = new QC_Request__c();
            qc.Unit__c = unit.Id;
            qc.Opportunity__c = unitToOpportunityMap.get(unit.Id);
            qc.OwnerId = qcOwner.Id;
            requestsToInsert.add(qc);
        }
        if (requestsToInsert.isEmpty()) {
            return;
        }
        insert requestsToInsert;

        // ===============================
        // Get Logo Content Assets
        // ===============================
        Map<String, ContentAsset> logoAssetsMap = new Map<String, ContentAsset>();
        for (ContentAsset asset : [SELECT Id,DeveloperName, MasterLabel, ContentDocumentId,IsVisibleByExternalUsers FROM ContentAsset WHERE DeveloperName IN ('Logo_White', 'Logo_Blue') WITH SYSTEM_MODE
        ]) {
            logoAssetsMap.put(asset.DeveloperName, asset);
        }

        String orgId = UserInfo.getOrganizationId();
        String orgDomainUrl = URL.getOrgDomainUrl().toExternalForm();
        String jkpWhiteLogoUrl = '';
        String jkpBlueLogoUrl = '';
        if (logoAssetsMap.containsKey('Logo_White')) {
            ContentAsset whiteLogo = logoAssetsMap.get('Logo_White');
            jkpWhiteLogoUrl = orgDomainUrl + '/file-asset-public/' + whiteLogo.DeveloperName + '?oid=' + orgId;
        }

        if (logoAssetsMap.containsKey('Logo_Blue')) {
            ContentAsset blueLogo = logoAssetsMap.get('Logo_Blue');
            jkpBlueLogoUrl = orgDomainUrl + '/file-asset-public/' + blueLogo.DeveloperName + '?oid=' + orgId;
        }

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        String unitRows = '';
        Map<Id, Unit__c> unitMap =new Map<Id, Unit__c>(unitsToUpdate);
        for (QC_Request__c qc : requestsToInsert) {
            Unit__c unit = unitMap.get(qc.Unit__c);
            if (unit == null) {
                continue;
            }
            String floorName = unit.Floor__r != null ? unit.Floor__r.Name : '';
            String blockName =unit.Floor__r != null && unit.Floor__r.Block__r != null  ? unit.Floor__r.Block__r.Name : '';
            String projectName = unit.Floor__r != null && unit.Floor__r.Block__r != null && unit.Floor__r.Block__r.Project__r != null ? unit.Floor__r.Block__r.Project__r.Name : '';
            // Unit r URL
            String unitUrl =baseUrl +'/lightning/r/Unit__c/' + unit.Id + '/view';
            // QC Request  URL
            String qcUrl = baseUrl +'/lightning/r/QC_Request__c/' + qc.Id +'/view';
            unitRows +='<tr>' +
                // UNIT NAME
                '<td style="' + 'padding:14px 10px;' +'border-bottom:1px solid #e5e9ee;' + '">' +
                    '<a href="' + unitUrl + '"' +' style="' + 'color:#1677c8;' + 'text-decoration:none;' +'font-weight:bold;' + 'font-size:13px;' +'">' +
                        unit.Name +
                    '</a>' +
                '</td>' +
                // UNIT CODE
                '<td style="' +'padding:14px 10px;' +'border-bottom:1px solid #e5e9ee;' +'font-size:12px;' +'color:#52606d;' +'">' +
                    (unit.Unit_Name_Code__c == null ? '' : unit.Unit_Name_Code__c) +
                '</td>' +
                // FLOOR
                '<td style="' +'padding:14px 10px;' +'border-bottom:1px solid #e5e9ee;' + 'font-size:12px;' + 'color:#52606d;' +'">' +
                    floorName +
                '</td>' +
                // BLOCK
                '<td style="' +'padding:14px 10px;' + 'border-bottom:1px solid #e5e9ee;' +'font-size:12px;' + 'color:#52606d;' + '">' +
                    blockName +
                '</td>' +
                // PROJECT
                '<td style="' + 'padding:14px 10px;' +'border-bottom:1px solid #e5e9ee;' +'font-size:12px;' + 'color:#52606d;' + '">' +
                    projectName +
                '</td>' +
                // VIEW REQUEST
                '<td style="' + 'padding:14px 10px;' + 'border-bottom:1px solid #e5e9ee;' +'">' +
                    '<a href="' + qcUrl + '"' + ' style="' + 'display:inline-block;' + 'background-color:#101f3d;' +'color:#ffffff;' + 'text-decoration:none;' + 'font-size:11px;' +  'font-weight:bold;' + 'padding:8px 11px;' + 'white-space:nowrap;' + '">' +
                        'View Request' +
                    '</a>' +
                '</td>' +
            '</tr>';
        } 
        List<EmailTemplate> templates = [SELECT Id,DeveloperName,HtmlValue,Subject FROM EmailTemplate WHERE DeveloperName = 'Email_For_New_QC_Request' LIMIT 1 ];

        if (templates.isEmpty()) {
            throw new AuraHandledException('QC notification email template was not found.');
        }
        EmailTemplate template = templates[0];
        String emailBody = template.HtmlValue;
        emailBody = emailBody.replace('{!Request_Count}',String.valueOf(requestsToInsert.size()));
        emailBody = emailBody.replace( '{!UNIT_ROWS}', unitRows);
        emailBody = emailBody.replace('{{JKP_LOGO_WHITE}}', jkpWhiteLogoUrl);
        emailBody = emailBody.replace('{{JKP_LOGO_BLUE}}', jkpBlueLogoUrl);
        System.debug('Final Email Subject: ' +( template.Subject != null? template.Subject : 'New QC Request (Unit-wise)') );
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{qcOwner.Email});
        email.setSubject( template.Subject != null? template.Subject:'New QC Request (Unit-wise)' );
        email.setHtmlBody(emailBody);
        System.debug('EMAIL TO: ' + qcOwner.Email);
        System.debug('EMAIL RECIPIENT NAME: ' +qcOwner.Name);

        Messaging.sendEmail( new List<Messaging.SingleEmailMessage>{email} );
        System.debug('EMAIL SENT TO: ' + qcOwner.Email );
    }
    
}