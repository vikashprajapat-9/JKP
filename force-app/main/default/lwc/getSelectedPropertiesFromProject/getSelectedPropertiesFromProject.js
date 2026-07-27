import { LightningElement, wire, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUnitRecordBasedOnProjectFilter from '@salesforce/apex/SelectPropertsiteVisitController.getProjectDetailsBasedonSearch';
import getCurrentUserProfileName from '@salesforce/apex/SelectPropertsiteVisitController.getCurrentUserProfileName';
import getProjectDetails from '@salesforce/apex/SelectPropertsiteVisitController.getProjectDetails';
import TOWER_IMAGE from "@salesforce/resourceUrl/towerImage";
import FAMILY_IMAGE from "@salesforce/resourceUrl/HomeBHK";
import ONEBHK from "@salesforce/resourceUrl/oneBHKPerson";
import TWOBHK from "@salesforce/resourceUrl/twoBHK";
import THREEBHK from "@salesforce/resourceUrl/threeBHK";

export default class GetSelectedPropertiesFromProject extends NavigationMixin(LightningElement) {
    towerimageurl = TOWER_IMAGE;
    homeimageulr = FAMILY_IMAGE;
    onebhk = ONEBHK;
    twobhk = TWOBHK;
    threebhk = THREEBHK;
    @track selectedProjectName;
    @track optionsprojectName = [];
    @track AvailableForSaleCount = 0;
    @track SoldCount = 0;
    @track ManagementBlockedCount = 0;
    @track UnderCustomerDiscussionCount = 0;
    @track NotReleasedbyManagementCount = 0;
    @track BlockedforSafetyClearanceCount = 0;
    @track waitingPaymentConfirmationCount = 0;
    @track error;
    @track wrapdata;
    @track TowersUnit = [];
    @track SlabsList = [];
    @track towerpicarray = [];
    @track TowerName = '';
    @track totalunits;
    @track selectedId;
    @track unitRecord;
    @track unitBoolean = false;
    @track FlatBhkId = '3 BR';
    floorUnitMap = new Map();
    @track floorUnitMapArray =[];


    connectedCallback() {
        debugger;
        setTimeout(() => {
            this.handleBHKClick();
            this.getProjectNamePickList();
        }, 300);
    }

    profileName;
      diasbleButton = false;

       @wire(getCurrentUserProfileName)
    wiredProfile({ error, data }) {
        debugger;
        if (data) {
            this.profileName = data;
            if(this.profileName == 'Admin' || this.profileName == 'System Administrator'){
                this.diasbleButton = true;
            }
            console.log('Current User Profile Name:', this.profileName);
        } else if (error) {
            console.error('Error fetching profile name:', error);
        }
    }


    getProjectNamePickList() {
        getProjectDetails()
            .then(result => {
                if (result.length > 0) {
                    this.optionsprojectName = result.map(item => ({ label: item.Name, value: item.Name }));
                }
            })
            .catch(error => {
                console.log('Error fetching picklist options ===> ' + error);
            });
    }


    mapToLabelValuePair(values) {
        return values.map(value => ({
            label: value, value: value
        }));
    }

    ProjecthandleChange(event) {
        this.selectedProjectName = event.detail.value;
    }

    handletowerselection(event) {
        debugger;
        const towerButtons = this.template.querySelectorAll('.towerbutton');
        towerButtons.forEach(button => {
            button.style.backgroundColor = '#D6D6D6'; 
            button.textContent = 'Select'; 
        });
    
        let clickedButton;
        if (event) {
            clickedButton = event.currentTarget;
            this.TowerName = event.target.dataset.eventId; 
        } 
        else if (this.TowerName) {
            clickedButton = Array.from(towerButtons).find(button => button.dataset.eventId === this.TowerName);
        }
        if (clickedButton) {
            clickedButton.style.backgroundColor = '#00A1E0';
            clickedButton.textContent = 'Selected';
        } else {
            console.error('No matching tower button found for TowerName:', this.TowerName);
        }
        if (event) {
            this.SearchUnits();
        }
        const tempLookingforpic = [];
        console.log('this.towerpicarray==>'+this.towerpicarray);
        this.towerpicarray.forEach(item => {
            if (item.id === this.TowerName) {
                tempLookingforpic.push({ id: item.id, value: item.value, towerselection: 'Selected' });
            } else {
                tempLookingforpic.push({ id: item.id, value: item.value, towerselection: 'Select' });
            }
        });
        this.towerpicarray = tempLookingforpic;
        console.log('this.towerpicarray==>'+this.towerpicarray);
    }

    ClearUnits(){
        this.selectedProjectName = null;
    }

    @track FloorListNumbers = [];
    SearchUnits() {
        debugger;
        if(this.selectedProjectName == null){
            this.showToast('Error', 'Please Select Project Name', 'error');
            return;
        }
        getUnitRecordBasedOnProjectFilter({ FlatBhkId: this.FlatBhkId, projectName: this.selectedProjectName, towerName: this.TowerName })
            .then((result) => {
                debugger;
                if(result != null ){
                    this.wrapdata = result;
                    var tempUnitArry = [];
                    var temptotalunits = 0;
                    this.TowerName = result.defaultTowerName != null ? result.defaultTowerName : null;
                    this.FlatBhkId = result.defaultFlatType != null ? result.defaultFlatType : null;
                    if(this.FlatBhkId != null){
                        this.handleBHKClick();
                    }

                    this.AvailableForSaleCount = result.AvailableforSale != null ? result.AvailableforSale : null;
                    this.waitingPaymentConfirmationCount = result.AwaitingPaymentConfirmation != null ? result.AwaitingPaymentConfirmation : null;
                    this.SoldCount = result.Sold != null ? result.Sold : null;
                    this.ManagementBlockedCount = result.ManagementBlocked != null ? result.ManagementBlocked : null;
                    this.UnderCustomerDiscussionCount = result.LandLord != null ? result.LandLord : null;
                    this.NotReleasedbyManagementCount = result.Blocked_NotReleasedbyMgmt != null ? result.Blocked_NotReleasedbyMgmt : null;
                    this.BlockedforSafetyClearanceCount = result.Blocked_ForFire_SafetyClearance != null ? result.Blocked_ForFire_SafetyClearance : null;

                    if (result.TowerPickistvalues.length > 0) {                    
                        let tempLookingforpic = [];
                        let tempLookingforarr = [];
                        for (let i = 0; i < result.TowerPickistvalues.length; i++) {
                            tempLookingforarr.push({ label: result.TowerPickistvalues[i], value: result.TowerPickistvalues[i] });
                        }
                        for (let i = 0; i < result.TowerPickistvalues.length; i++) {
                            if (this.towerName != null && this.towerName != undefined && temptowerpicarray[i].id == this.towerName) {
                                tempLookingforpic.push({ id: result.TowerPickistvalues[i], value: result.TowerPickistvalues[i], towerselection: 'Selected' });
                            }
                            else {
                                tempLookingforpic.push({ id: result.TowerPickistvalues[i], value: result.TowerPickistvalues[i], towerselection: 'Select' });
                            }
                        }
                        console.log('tempLookingforpic==>'+tempLookingforpic);
                        this.TowerPicklist = tempLookingforarr != null ? tempLookingforarr : null;
                        this.TowerPicklist.sort((a, b) => (a.label > b.label) ? 1 : -1);
                        this.towerpicarray = tempLookingforpic != null ? tempLookingforpic : null;
                        this.towerpicarray.sort((a, b) => (a.id > b.id) ? 1 : -1);
                        console.log('Picklistvalue===> ', this.TowerPicklist);
                    }
                    if(this.TowerName != null){
                        this.handletowerselection();
                    }
    
                    if (result.FloorwithunitMapDetails) {
                        for (let key in result.FloorwithunitMapDetails) {
                            var tempobject = {};
                            tempobject.unitName = key;
                            tempobject.Id = key;
                            tempobject.hasFloorDetails = false;
                            tempobject.mainFloor;
                            var tempinnerunitarray = [];
                            for (let j = 0; j < result.FloorwithunitMapDetails[key].length; j++) {
                                if (result.FloorwithunitMapDetails[key][j].Floor__r.Block__r.Block_Code__c == this.TowerName && result.FloorwithunitMapDetails[key][j].Unit_Type__c == this.FlatBhkId) {
                                    temptotalunits = temptotalunits + 1;
                                    if (result.FloorwithunitMapDetails[key][j].Floor__r.Floor_No__c != null && tempobject.hasFloorDetails == false){
                                        tempobject.hasFloorDetails = true;
                                        tempobject.mainFloor = result.FloorwithunitMapDetails[key][j].Floor__r.Floor_No__c;
                                    }
                                    if (result.FloorwithunitMapDetails[key][j].Status__c == 'Z0') {
                                        // result.FloorwithunitMapDetails[key][j].Classvisibilty = 'greenClass';
                                        result.FloorwithunitMapDetails[key][j].newClass = 'greenClass';
                                        tempinnerunitarray.push(result.FloorwithunitMapDetails[key][j]);
                                    }
                                    if (result.FloorwithunitMapDetails[key][j].Status__c == 'Z1') {
                                        // result.FloorwithunitMapDetails[key][j].Classvisibilty = 'amberClass';
                                        result.FloorwithunitMapDetails[key][j].newClass = 'amberClass';
                                        tempinnerunitarray.push(result.FloorwithunitMapDetails[key][j]);
                                    }
                                    if (result.FloorwithunitMapDetails[key][j].Status__c == 'Z2') {
                                        // result.FloorwithunitMapDetails[key][j].Classvisibilty = 'purpleClass';
                                        result.FloorwithunitMapDetails[key][j].newClass = 'purpleClass';
                                        tempinnerunitarray.push(result.FloorwithunitMapDetails[key][j]);
                                    }
                                    if (result.FloorwithunitMapDetails[key][j].Status__c == 'Z3') {
                                        // result.FloorwithunitMapDetails[key][j].Classvisibilty = 'yellowClass';
                                        result.FloorwithunitMapDetails[key][j].newClass = 'yellowClass';
                                        tempinnerunitarray.push(result.FloorwithunitMapDetails[key][j]);
                                    }
                                    if (result.FloorwithunitMapDetails[key][j].Status__c == 'Z4') {
                                        // result.FloorwithunitMapDetails[key][j].Classvisibilty = 'brownClass';
                                        result.FloorwithunitMapDetails[key][j].newClass = 'brownClass';
                                        tempinnerunitarray.push(result.FloorwithunitMapDetails[key][j]);
                                    }
                                                                 
                                }
                            }
                            tempobject.unitdetails = tempinnerunitarray;
                            tempUnitArry.push(tempobject);
                        }
                    }
                    this.SlabsList = result.getSlabsListFromUnit != null ? result.getSlabsListFromUnit : null;
                    this.FloorListNumbers = [];
                    this.SlabsList.forEach((item) => {
                        if (!this.FloorListNumbers.includes(item.Floor_No__c)) { 
                            this.FloorListNumbers.push(item.Floor_No__c); 
                        }
                    });
                    console.log('this.FloorListNumbers ===> ' + this.FloorListNumbers);
                    console.log('this.SlabsList==>' + this.SlabsList.length);
                    this.SlabsList.sort((a, b) => (a.Floor_No__c < b.Floor_No__c) ? 1 : -1);
                    this.TowersUnit = tempUnitArry;
                    // this.TowersUnit.sort((a, b) => (a.Id < b.Id) ? 1 : -1);
                    // this.TowersUnit = this.TowersUnit.filter(unit =>
                    //     this.TowersUnit.some(detail => detail.Id === unit.Id)
                    // );
    
                    const floorsInUnits = new Set();
                    this.TowersUnit.forEach(tower => {
                        tower.unitdetails.forEach(unit => {
                            const floorNumber = unit.Floor__r.Floor_No__c;
                            floorsInUnits.add(floorNumber);
                        });
                    });
    
                    const uniqueFloorsInUnits = Array.from(floorsInUnits);
                    const missingFloors = this.FloorListNumbers.filter(floor => !uniqueFloorsInUnits.includes(floor));
    
                    this.TowersUnit.forEach(tower => {
                        missingFloors.forEach(floor => {
                            const floorExists = this.TowersUnit.some(tower => tower.mainFloor === floor);
                            if (!floorExists) {
                                const tempTowerData = {
                                    Id : null,
                                    hasFloorDetails : false,
                                    mainFloor : floor
                                };
                                this.TowersUnit.push(tempTowerData);
                            } 
                        });
                    });
    
                    this.TowersUnit.sort((a, b) => {
                        const floorA = a.mainFloor || Number.MIN_SAFE_INTEGER; 
                        const floorB = b.mainFloor || Number.MIN_SAFE_INTEGER; 
                        return floorB - floorA; 
                    });   
                    console.log('this.TowersUnit==>'+this.TowersUnit);
                    this.buildFloorUnitMap();

                    this.totalunits = temptotalunits;
                }else{
                    this.TowersUnit = [];
                    this.SlabsList = [];
                    this.totalunits = 0;
                    this.towerpicarray = [];
                    this.AvailableForSaleCount = 0;
                    this.SoldCount = 0;
                    this.ManagementBlockedCount = 0;
                    this.UnderCustomerDiscussionCount = 0;
                    this.NotReleasedbyManagementCount = 0;
                    this.BlockedforSafetyClearanceCount = 0;
                    this.waitingPaymentConfirmationCount = 0;
                }
            })
            .catch((error) => {
                this.error = error;
            });
    }

    buildFloorUnitMap() {
        debugger;
        let floorUnitMap = new Map();
        this.TowersUnit.forEach(floor => {
            if (floor.unitdetails && Array.isArray(floor.unitdetails)) {
                floorUnitMap.set(floor.mainFloor, { floorDetails: floor, units: floor.unitdetails });
            }
        });
        this.floorUnitMapArray = Array.from(floorUnitMap, ([floorNumber, data]) => ({
            floorNumber: floorNumber,
            floorDetails: data.floorDetails,
            units: data.units
        }));
        console.log('this.floorUnitMapArray:', this.floorUnitMapArray);
    }
    
    handleBHKClick(event) {
        debugger;
        const buttons = this.template.querySelectorAll('.buttonBHK');
        buttons.forEach(button => {
            button.style.backgroundColor = '#D6D6D6';
            button.textContent = 'Select';
        });
        let clickedButton;
        if (event) {
            clickedButton = event.currentTarget;
            this.FlatBhkId = event.target.dataset.eventId; 
        } 
        else if (this.FlatBhkId) {
            clickedButton = Array.from(buttons).find(button => button.dataset.eventId === this.FlatBhkId);
        }
        if (clickedButton) {
            clickedButton.style.backgroundColor = '#00A1E0';
            clickedButton.textContent = 'Selected';
        }
        if (event) {
            this.SearchUnits();
        }
    }
    
    handleDivClick(event) {
        const clickedId = event.currentTarget.getAttribute('data-event-id');
        this.selectedId = clickedId; 
        console.log('Clicked ID:', clickedId);
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedId,
                objectApiName: 'Unit__c', 
                actionName: 'view'
            }
        });
    }

    handleClose() {
        this.unitBoolean = false;
    }

    handleMouseOver(event) {
        const itemId = event.currentTarget.dataset.id;
        const tooltip = this.template.querySelector(`#tooltip-${itemId}`);
        const unitType = event.currentTarget.dataset.unitType || 'N/A';
        const slab = event.currentTarget.dataset.slab || 'N/A';
        const status = event.currentTarget.dataset.status || 'N/A';
        const tower = event.currentTarget.dataset.tower || 'N/A';

        tooltip.innerHTML = `
        <strong>Unit Type:</strong> ${unitType}<br>
        <strong>Slab:</strong> ${slab}<br>
        <strong>Status:</strong> ${status}<br>
        <strong>Tower:</strong> ${tower}
    `;
        const rect = event.currentTarget.getBoundingClientRect();
        tooltip.style.left = `${rect.left + window.scrollX}px`;
        tooltip.style.top = `${rect.top + window.scrollY - tooltip.offsetHeight - 5}px`;
        tooltip.style.display = 'block';
    }

    handleMouseOut(event) {
        debugger;
        const itemId = event.currentTarget.dataset.id;
        const tooltip = this.template.querySelector(`#tooltip-${itemId}`);
        tooltip.style.display = 'none'; 
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }
}