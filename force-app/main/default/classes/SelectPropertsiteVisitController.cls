/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : SelectPropertsiteVisitController
 * Author          : <YourName>
 * Created Date    : Jul 23, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 23, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 23, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public without sharing class SelectPropertsiteVisitController {

        @AuraEnabled(cacheable=true)
    public static String getCurrentUserProfileName() {
        String profileName =  [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() Limit 1].Profile.Name;
        System.debug('profileName==>'+profileName);
        return profileName;
    }

    
    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjectDetails(){
        List<Project__c> projectList = [SELECT Id,Name from Project__c]; 
        if(projectList.size() > 0){
            return projectList;
        }
        return null;
    }
    
    @AuraEnabled(cacheable= true)
    public static List<String> getPicklistValues(String objName, String fieldName){
        List<String> options = new List<String>();
        Map<String, String> mapPickListValues = new Map<String, String>();
        Schema.SObjectType objSobjectType = Schema.getGlobalDescribe().get(objName);
        Schema.DescribeSObjectResult objDescribeSobject = objSobjectType.getDescribe();
        Map<String, Schema.SObjectField> mapFields = objDescribeSobject.fields.getMap();
        List<Schema.PicklistEntry> lstPickListValues = mapFields.get(fieldName).getDescribe().getPickListValues();
        for (Schema.PicklistEntry objPickList : lstPickListValues) {
            options.add(objPickList.getValue());
        }
        return options;
    }
    
    @AuraEnabled
    public static SelectPropertiesWrappper getProjectDetailsBasedonSearch(String projectName,String FlatBhkId, String towerName){ 
        System.debug(' projectName ===> ' + projectName + ' towerName===> '  +towerName) ;
        SelectPropertiesWrappper untiwrap = new SelectPropertiesWrappper();
        List<Unit__c> getUnitBasedProjectQuery = new List<Unit__c>();
        Set<Id> ProjectIdSet = new Set<Id>();
        Set<Id> SlabsIdSet = new Set<Id>();
        Integer AvailableForSaleCount = 0;
        Integer SoldCount = 0;
        Integer ManagementBlockedCount = 0;
        Integer landLordCount = 0;
        Integer NotReleasedbyManagementCount = 0;
        Integer BlockedforSafetyClearanceCount = 0;
        Integer waitingPaymentConfirmationCount = 0;
        map<String, List<Unit__c>> FloorwithunitMap = new map<String, List<Unit__c>>();
        
        try{
            List<Project__c> getAllProjectRecordsList = [SELECT Id,Name FROM Project__c WHERE Name=:projectName];
            System.debug('getAllProjectRecordsList ===> ' + getAllProjectRecordsList);
            if(getAllProjectRecordsList.size()>0){
                for(Project__c pro : getAllProjectRecordsList){
                    ProjectIdSet.add(pro.id);
                }

                if(ProjectIdSet.size()>0){
                    List<Block__c> towers = [SELECT Id, Name,Block_Code__c FROM Block__c WHERE Project__r.Name = :projectName order by Name ASC];
                    System.debug('towers ===> ' + towers);
                    Set<String> towerNamesSet = new Set<String>();
                    List<String> towerPicklist;
                    if(towers.size() > 0){
                        for (Block__c tower : towers) {
                            towerNamesSet.add(tower.Block_Code__c);
                        }
                        towerPicklist = new List<String>(towerNamesSet);
                        untiwrap.TowerPickistvalues = towerPicklist;
                        System.debug('untiwrap.TowerPickistvalues===>'+untiwrap.TowerPickistvalues);
                    }

                    String defaultTower = towerPicklist.contains(towerName) ? towerName : towerPicklist[0];
                    System.debug('defaultTower ==> ' + defaultTower);
                    List<Floor__c> projectTowerSlabs = [SELECT  Floor_No__c, Id, Name,Block__c,Block__r.Block_Code__c, (SELECT Id,Name,Floor__c FROM Units__r) FROM Floor__c WHERE Block__r.Block_Code__c =: defaultTower ORDER By Floor_No__c DESC];
                    System.debug('projectTowerSlabs==>' +projectTowerSlabs);
                    Set<Id> floorIds = new Set<Id>();
                    if(projectTowerSlabs.size() > 0){
                        for(Floor__c floor : projectTowerSlabs){
                            floorIds.add(floor.Id);
                        }
                        untiwrap.getSlabsListFromUnit =projectTowerSlabs;
                        System.debug('untiwrap.getSlabsListFromUnit ===> ' + untiwrap.getSlabsListFromUnit);
                    }
                    System.debug('floorIds==>'+floorIds);
                    
                    String defaultUnitType = FlatBhkId == null ? '1 BHK' : FlatBhkId;
                    System.debug('defaultUnitType ==> ' + defaultUnitType);
                    List<Unit__c> units = [SELECT Id,Name,Unit_Name_Code__c,Status__c,Floor__c, Floor__r.Name,Floor__r.Floor_No__c,Unit_Type__c,Floor__r.Block__r.Name,Floor__r.Block__r.Block_Code__c FROM Unit__c  WHERE  Floor__c IN: floorIds and Unit_Type__c =: defaultUnitType];
                    System.debug('units size==>'+ units.size());
                    untiwrap.defaultTowerName = defaultTower != null ? defaultTower : null;
                    untiwrap.defaultFlatType = defaultUnitType != null ? defaultUnitType : null;

                    for(Unit__c unit : units ){
                        System.debug('unit ===> ' + unit);
                        System.debug('unit status ===> ' + unit.Status__c);
                        if(String.isNotBlank(unit.Status__c)){
                            AvailableForSaleCount           = (unit.Status__c == 'Z0') ? AvailableForSaleCount + 1 : AvailableForSaleCount;
                            SoldCount                       = (unit.Status__c =='Z1') ? SoldCount + 1 : SoldCount;
                            ManagementBlockedCount          = (unit.Status__c =='Z2') ? ManagementBlockedCount + 1 : ManagementBlockedCount;
                            landLordCount    = (unit.Status__c =='Z3') ? landLordCount + 1 : landLordCount;
                            NotReleasedbyManagementCount    = (unit.Status__c =='Z4') ? NotReleasedbyManagementCount + 1 : NotReleasedbyManagementCount;
                            
                        }
                        if (FloorwithunitMap.containsKey(unit.Floor__r.Name)){
                            List<Unit__c> ExistingUnitlist = FloorwithunitMap.get(unit.Floor__r.Name);
                            if (unit.Status__c != null){
                                ExistingUnitlist.add(unit);
                            }
                            FloorwithunitMap.put(unit.Floor__r.Name, ExistingUnitlist);
                        } else{
                            List<Unit__c> NewUnitlist = new List<Unit__c>();
                            NewUnitlist.add(unit);
                            FloorwithunitMap.put(unit.Floor__r.Name, NewUnitlist);
                        }
                        untiwrap.FloorwithunitMapDetails = FloorwithunitMap;
                    }
                    if(AvailableForSaleCount !=null){
                        untiwrap.AvailableforSale = AvailableForSaleCount;
                    }
                    if(SoldCount !=null){
                        untiwrap.Sold = SoldCount;
                    }
                    if(ManagementBlockedCount !=null){
                        untiwrap.ManagementBlocked = ManagementBlockedCount;
                    }
                    if(landLordCount !=null){
                        untiwrap.LandLord = landLordCount;
                    }
                    if(NotReleasedbyManagementCount !=null){
                        untiwrap.Blocked_NotReleasedbyMgmt = NotReleasedbyManagementCount;
                    }
                    if(BlockedforSafetyClearanceCount !=null){
                        untiwrap.Blocked_ForFire_SafetyClearance = BlockedforSafetyClearanceCount;
                    }
                    if(waitingPaymentConfirmationCount !=null){
                        untiwrap.AwaitingPaymentConfirmation = waitingPaymentConfirmationCount;
                    }
                    if(getUnitBasedProjectQuery.size()>0){
                        untiwrap.getUnitRecordBasedOnProjectList = getUnitBasedProjectQuery;
                    }
                    
                    if(untiwrap !=null){
                        System.debug('untiwrap.FloorwithunitMapDetails ===> ' + untiwrap.FloorwithunitMapDetails);
                        System.debug('untiwrap == >'+untiwrap);
                        return untiwrap;
                    }
                }
            }else{
                return null;
            }
        }catch(Exception e){
            System.debug('The Error ::'+e.getMessage() +' AND Error Line No :'+e.getLineNumber());
        }
        return null;
    }
    
    public class SelectPropertiesWrappper{
        @AuraEnabled public List<Unit__c> getUnitRecordBasedOnProjectList { get; set; }
        @AuraEnabled public List<Floor__c> getSlabsListFromUnit { get; set; }
        @AuraEnabled public map<String, List<Unit__c>> FloorwithunitMapDetails{ get; set; }
        @AuraEnabled public Integer AvailableforSale { get; set; }
        @AuraEnabled public Integer AwaitingPaymentConfirmation { get; set; }
        @AuraEnabled public Integer Sold { get; set; }
        @AuraEnabled public Integer ManagementBlocked { get; set; }
        @AuraEnabled public Integer LandLord { get; set; }
        @AuraEnabled public Integer Blocked_NotReleasedbyMgmt { get; set; }
        @AuraEnabled public Integer Blocked_ForFire_SafetyClearance { get; set; }
        @AuraEnabled public List<String> TowerPickistvalues{ get; set; }
        @AuraEnabled public String defaultTowerName { get; set; }
        @AuraEnabled public String defaultFlatType { get; set; }
    }
    
    @AuraEnabled(cacheable=true)
    public static Unit__c getUnitRecord(String recordId) {
        return [SELECT Id, Name, Unit_Name_Code__c, Status__c, Floor__c, Floor__r.Name, Floor__r.Floor_No__c, Unit_Type__c FROM Unit__c WHERE Id = :recordId LIMIT 1];
    }
}