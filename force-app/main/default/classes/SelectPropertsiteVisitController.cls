public without sharing class SelectPropertsiteVisitController {

    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjectDetails() {
        List<Project__c> projectList = [SELECT Id, Name FROM Project__c ORDER BY Name];
        if(projectList.size() > 0){
            return projectList;
        }
        return null;
    }

    @AuraEnabled(cacheable= true)
    public static Map<String, List<String>> getAllPickListVal(Map<String, String> ObjectByField) {
        Map<String, List<String>> picklistValByField = new Map<String, List<String>>();
        for (String fields : ObjectByField.keySet()) {
            picklistValByField.put(fields, getPicklistValues(ObjectByField.get(fields), fields));
        }
        return picklistValByField;
    }

    @AuraEnabled(cacheable= true)
    public static List<String> getPicklistValues(String objName, String fieldName) {
        List<String> options = new List<String>();
        Schema.SObjectType objSobjectType = Schema.getGlobalDescribe().get(objName);
        Schema.DescribeSObjectResult objDescribeSobject = objSobjectType.getDescribe();
        Map<String, Schema.SObjectField> mapFields = objDescribeSobject.fields.getMap();
        List<Schema.PicklistEntry> lstPickListValues = mapFields.get(fieldName).getDescribe().getPickListValues();
        for (Schema.PicklistEntry objPickList : lstPickListValues) {
            options.add(objPickList.getValue());
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getTowersByProject(String projectName) {
        system.debug('projectName:::>>' + projectName);
        List<String> towerCodes = new List<String>();
        if (String.isBlank(projectName)) {
            return towerCodes;
        }

        List<Block__c> towers = [SELECT Block_Code__c FROM Block__c WHERE Project__r.Name = :projectName ORDER BY Name];
        for (Block__c t : towers) {
            if (String.isNotBlank(t.Block_Code__c)) {
                towerCodes.add(t.Block_Code__c);
            }
        }
        return towerCodes;
    }

    @AuraEnabled
    public static SelectPropertiesWrappper getProjectDetailsBasedonSearch(String FlatBhkId, String projectName, String towerName, String unitType) {
        System.debug('projectName ===> ' + projectName +
                    ' towerName ===> ' + towerName +
                    ' FlatBhkId ===> ' + FlatBhkId +
                    ' unitType ===> ' + unitType);

        SelectPropertiesWrappper untiwrap = new SelectPropertiesWrappper();

        Integer AvailableForSaleCount = 0;
        Integer SoldCount = 0;
        Integer ManagementBlockedCount = 0;
        Integer UnderCustomerDiscussionCount = 0;
        Integer NotReleasedbyManagementCount = 0;
        Integer BlockedforSafetyClearanceCount = 0;
        Integer waitingPaymentConfirmationCount = 0;

        Map<String, List<Unit__c>> FloorwithunitMap = new Map<String, List<Unit__c>>();

        try {
            if (String.isBlank(projectName)) {
                return null;
            }

            List<Project__c> projects = [SELECT Id, Name FROM Project__c WHERE Name = :projectName LIMIT 1];

            if (projects.isEmpty()) {
                return null;
            }

            Id projectId = projects[0].Id;
            system.debug('projectId::=>> ' + projectId);

            List<Block__c> towers = [SELECT Id, Name, Block_Code__c FROM Block__c WHERE Project__c = :projectId ORDER BY Name ASC];

            if (towers.isEmpty()) {
                return null;
            }

            Set<String> towerNamesSet = new Set<String>();
            for (Block__c t : towers) {
                if (String.isNotBlank(t.Block_Code__c)) {
                    towerNamesSet.add(t.Block_Code__c);
                }
            }
            List<String> towerPicklist = new List<String>(towerNamesSet);
            towerPicklist.sort();
            untiwrap.TowerPickistvalues = towerPicklist;

            // No tower selected -> show units of every tower under the project
            String effectiveTower = towerName;
            untiwrap.defaultTowerName = effectiveTower;

            List<Floor__c> projectTowerSlabs = new List<Floor__c>();
            Set<Id> floorIds = new Set<Id>();

            if (!String.isBlank(effectiveTower)) {
                projectTowerSlabs = [SELECT Id, Name, Floor_No__c, Block__c, Block__r.Block_Code__c, (SELECT Id, Name, Floor__c FROM Units__r) FROM Floor__c WHERE Block__r.Block_Code__c = :effectiveTower AND Block__r.Project__c = :projectId ORDER BY Floor_No__c DESC
                ];
            } else {
                projectTowerSlabs = [SELECT Id, Name, Floor_No__c, Block__c, Block__r.Block_Code__c, (SELECT Id, Name, Floor__c FROM Units__r) FROM Floor__c WHERE Block__c IN :towers ORDER BY Floor_No__c DESC
                ];
            }

            for (Floor__c f : projectTowerSlabs) {
                floorIds.add(f.Id);
            }

            untiwrap.getSlabsListFromUnit = projectTowerSlabs;
            System.debug('floorIds:::>> ' + floorIds);

            String filterUnitType = !String.isBlank(unitType) ? unitType : (!String.isBlank(FlatBhkId) ? FlatBhkId : null);
            System.debug('filterUnitType:::>> ' + filterUnitType);
            untiwrap.defaultFlatType = filterUnitType;

            List<Unit__c> units = new List<Unit__c>();
            if (!floorIds.isEmpty()) {
                String baseQuery =
                    'SELECT Id, Name, Unit_Name_Code__c, Status__c, Unit_Type__c,' +
                    ' Super_Built_Up_Area_sq_ft__c, Base_Price_per_sqft__c, Floor_Rise__c,' +
                    ' Floor__c, Floor__r.Name, Floor__r.Floor_No__c,' +
                    ' Floor__r.Block__r.Name, Floor__r.Block__r.Block_Code__c' +
                    ' FROM Unit__c WHERE Floor__c IN :floorIds';

                if (!String.isBlank(filterUnitType)) {
                    baseQuery += ' AND Unit_Type__c = :filterUnitType';
                    units = Database.query(baseQuery);
                } else {
                    units = Database.query(baseQuery);
                }
            }

            untiwrap.getUnitRecordBasedOnProjectList = units;

            for (Unit__c unit : units) {
                if (!String.isBlank(unit.Status__c)) {
                    if (unit.Status__c == 'Z1') {
                        AvailableForSaleCount++;
                    } else if (unit.Status__c == 'Z3') {
                        SoldCount++;
                    } else if (unit.Status__c == 'Z0') {
                        ManagementBlockedCount++;
                    } else if (unit.Status__c == 'Z2') {
                        waitingPaymentConfirmationCount++;
                    }
                }

                String floorKey = unit.Floor__r.Name;
                system.debug('floorKey:::>> ' + floorKey);
                if (FloorwithunitMap.containsKey(floorKey)) {
                    FloorwithunitMap.get(floorKey).add(unit);
                } else {
                    FloorwithunitMap.put(floorKey, new List<Unit__c>{ unit });
                }
            }

            untiwrap.FloorwithunitMapDetails = FloorwithunitMap;

            untiwrap.AvailableforSale                = AvailableForSaleCount;
            untiwrap.Sold                            = SoldCount;
            untiwrap.ManagementBlocked               = ManagementBlockedCount;
            untiwrap.UnderCustomerDiscussion         = UnderCustomerDiscussionCount;
            untiwrap.Blocked_NotReleasedbyMgmt       = NotReleasedbyManagementCount;
            untiwrap.Blocked_ForFire_SafetyClearance = BlockedforSafetyClearanceCount;
            untiwrap.AwaitingPaymentConfirmation     = waitingPaymentConfirmationCount;

            return untiwrap;
        } catch (Exception e) {
            System.debug('The Error :: ' + e.getMessage() + ' AND Error Line No :' + e.getLineNumber());
            return null;
        }
    }

    public class SelectPropertiesWrappper {
        @AuraEnabled public List<Unit__c>  getUnitRecordBasedOnProjectList { get; set; }
        @AuraEnabled public List<Floor__c> getSlabsListFromUnit            { get; set; }
        @AuraEnabled public Map<String, List<Unit__c>> FloorwithunitMapDetails { get; set; }
        @AuraEnabled public Integer AvailableforSale                       { get; set; }
        @AuraEnabled public Integer AwaitingPaymentConfirmation            { get; set; }
        @AuraEnabled public Integer Sold                                   { get; set; }
        @AuraEnabled public Integer ManagementBlocked                      { get; set; }
        @AuraEnabled public Integer UnderCustomerDiscussion                { get; set; }
        @AuraEnabled public Integer Blocked_NotReleasedbyMgmt              { get; set; }
        @AuraEnabled public Integer Blocked_ForFire_SafetyClearance        { get; set; }
        @AuraEnabled public List<String> TowerPickistvalues                { get; set; }
        @AuraEnabled public String defaultTowerName                        { get; set; }
        @AuraEnabled public String defaultFlatType                         { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static Unit__c getUnitRecord(String recordId) {
        return [SELECT Id, Name, Unit_Name_Code__c, Status__c, Floor__c, Floor__r.Name, Floor__r.Floor_No__c, Unit_Type__c FROM Unit__c WHERE Id = :recordId LIMIT 1];
    }
}