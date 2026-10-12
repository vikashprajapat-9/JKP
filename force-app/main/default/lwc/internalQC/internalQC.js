import { LightningElement, track } from 'lwc';
import getCompanies from '@salesforce/apex/UnitSelectorController.getCompanies';
import getProjects from '@salesforce/apex/UnitSelectorController.getProjects';
import getTowers from '@salesforce/apex/UnitSelectorController.getTowers';
import getFloors from '@salesforce/apex/UnitSelectorController.getFloors';
import getUnits from '@salesforce/apex/UnitSelectorController.getUnits';
import updateInternalQC from '@salesforce/apex/UnitSelectorController.updateInternalQC';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class UnitSelector extends LightningElement {

    @track companyOptions = [];
    @track projectOptions = [];
    @track towerOptions = [];
    @track floorOptions = [];
    @track unitOptions = [];

    @track selectedUnits = [];

    selectedCompanyId;
    selectedProjectId;
    selectedTowerId;
    selectedFloorId;

    selectedTowerName;
    selectedFloorName;

    isUpdating = false;

    connectedCallback() {
        this.loadCompanies();
    }
    loadCompanies() {
        getCompanies()
            .then(result => {
                this.companyOptions = result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }));
            })
            .catch(error => {
                this.showError(error);
            });
    }

    handleCompanyChange(event) {
        this.selectedCompanyId = event.detail.value;
        this.selectedProjectId = null;
        this.selectedTowerId = null;
        this.selectedFloorId = null;
        this.projectOptions = [];
        this.towerOptions = [];
        this.floorOptions = [];
     //   this.unitOptions = [];

        this.selectedTowerName = null;
        this.selectedFloorName = null;

        this.loadProjects();
        this.loadUnits();
    }
    loadProjects() {
        getProjects({
            companyId: this.selectedCompanyId
        })
            .then(result => {
                this.projectOptions = result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }));
            })
            .catch(error => {
                this.showError(error);
            });
        
    }

    handleProjectChange(event) {
        this.selectedProjectId = event.detail.value;
        this.selectedTowerId = null;
        this.selectedFloorId = null;
        this.towerOptions = [];
        this.floorOptions = [];
       // this.unitOptions = [];
        this.selectedTowerName = null;
        this.selectedFloorName = null;
        this.loadTowers();
        this.loadUnits();
    }
    loadTowers() {
        getTowers({
            projectId: this.selectedProjectId
        })
            .then(result => {
                this.towerOptions = result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }));
            })
            .catch(error => {
                this.showError(error);
            });
    }

    handleTowerChange(event) {
        this.selectedTowerId = event.detail.value;
        const selectedTower = this.towerOptions.find(
            item => item.value === this.selectedTowerId
        );
        this.selectedTowerName = selectedTower ? selectedTower.label : null;
        this.selectedFloorId = null;
        this.floorOptions = [];
       // this.unitOptions = [];
        this.selectedFloorName = null;
        this.loadFloors();
        this.loadUnits();
    }
    loadFloors() {
        getFloors({
            towerId: this.selectedTowerId
        })
            .then(result => {
                this.floorOptions = result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }));
            })
            .catch(error => {
                this.showError(error);
            });
        
    }

    handleFloorChange(event) {
        this.selectedFloorId = event.detail.value;
        const selectedFloor = this.floorOptions.find(
            item => item.value === this.selectedFloorId
        );
        this.selectedFloorName =selectedFloor ? selectedFloor.label : null;
        this.loadUnits();
    }
    loadUnits() {
        getUnits({
            companyId: this.selectedCompanyId,
            projectId: this.selectedProjectId,
            towerId: this.selectedTowerId,
            floorId: this.selectedFloorId
        })
            .then(result => {
                this.unitOptions = result.map(item => {
                    const isSelected = this.selectedUnits.some(
                        selected => selected.id === item.Id
                    );

                    return {
                        label: item.Name,
                        value: item.Id,
                        code: item.Unit_Name_Code__c,
                        cssClass: isSelected ? 'unit-card selected' : 'unit-card'
                    };
                });

            })
            .catch(error => {
                this.showError(error);
            });
    }
    
    handleUnitClick(event) {
        const unitId = event.currentTarget.dataset.id;
        const unit = this.unitOptions.find(
            item => item.value === unitId
        );
        if (!unit) {
            return;
        }
        const alreadySelected = this.selectedUnits.some(
            item => item.id === unitId
        );
        if (alreadySelected) {
            this.selectedUnits = this.selectedUnits.filter(
                item => item.id !== unitId
            );
        } else {
            this.selectedUnits = [
                ...this.selectedUnits,
                {
                    id: unit.value,
                    name: unit.label,
                    code: unit.code,
                    projectId: this.selectedProjectId,
                    towerId: this.selectedTowerId,
                    floorId: this.selectedFloorId
                }
            ];
        }
        this.updateUnitStyles();
    }
    removeUnit(event) {
        const unitId = event.currentTarget.dataset.id;
        this.selectedUnits = this.selectedUnits.filter(
            unit => unit.id !== unitId
        );
        this.updateUnitStyles();
    }
    updateUnitStyles() {
        this.unitOptions = this.unitOptions.map(unit => {
            const selected = this.selectedUnits.some(
                item => item.id === unit.value
            );

            return {
                ...unit,
                cssClass: selected ? 'unit-card selected' : 'unit-card'
            };
        });
    }
    handleUpdateInternalQC() {
        if (!this.selectedUnits.length) {
            this.showToast(
                'Warning',
                'Please select at least one unit.',
                'warning'
            );

            return;
        }
        this.isUpdating = true;
        const unitIds = this.selectedUnits.map(
            unit => unit.id
        );
        updateInternalQC({
            unitIds: unitIds
        })
            .then(() => {

                this.showToast(
                    'Success',
                    'Internal QC updated successfully.',
                    'success'
                );
                setTimeout(() => {
                    window.location.reload();
                }, 1000);

            })
            .catch(error => {
                this.showError(error);
            })
            .finally(() => {
                this.isUpdating = false;
            });
    }

    get isProjectDisabled() {
        return !this.selectedCompanyId;
    }
    get isTowerDisabled() {
        return !this.selectedProjectId;
    }
    get isFloorDisabled() {
        return !this.selectedTowerId;
    }
    get showUnits() {
        return  this.unitOptions.length > 0; //this.selectedFloorId &&
    }
    get hasSelectedUnits() {
        return this.selectedUnits.length > 0;
    }
    get isAllUnitsSelected() {
        return (
            this.unitOptions.length > 0 &&
            this.unitOptions.every(unit =>
                this.selectedUnits.some(
                    selected => selected.id === unit.value
                )
            )
        );
    }
    handleSelectAll(event) {

    const isChecked = event.target.checked;

    if (isChecked) {

        const selectedUnitIds = new Set(
            this.selectedUnits.map(unit => unit.id)
        );

        const newUnits = this.unitOptions
            .filter(unit => !selectedUnitIds.has(unit.value))
            .map(unit => ({
                id: unit.value,
                name: unit.label,
                code: unit.code,
                projectId: this.selectedProjectId,
                towerId: this.selectedTowerId,
                floorId: this.selectedFloorId
            }));

        this.selectedUnits = [
            ...this.selectedUnits,
            ...newUnits
        ];

    } else {

        // Remove currently displayed units
        const visibleUnitIds = new Set(
            this.unitOptions.map(unit => unit.value)
        );

        this.selectedUnits =
            this.selectedUnits.filter(
                unit => !visibleUnitIds.has(unit.id)
            );
    }

    this.updateUnitStyles();
}
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }

    showError(error) {
        let message = 'Something went wrong.';
        if (error?.body?.message) {
            message = error.body.message;
        }
        this.showToast(
            'Error',
            message,
            'error'
        );
        console.error(error);
    }
}