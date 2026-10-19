import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getUnitRecordBasedOnProjectFilter from '@salesforce/apex/SelectPropertsiteVisitController.getProjectDetailsBasedonSearch';
import getPicklistValuesDynamically from '@salesforce/apex/SelectPropertsiteVisitController.getAllPickListVal';
import getProjectDetails from '@salesforce/apex/SelectPropertsiteVisitController.getProjectDetails';
import getTowersByProject from '@salesforce/apex/SelectPropertsiteVisitController.getTowersByProject';

const ALL = '__ALL__';

// Unit statuses shown as tiles; anything else falls under "Other"
const STATUS_CONFIG = [
    { value: 'Z1', key: 'available', label: 'Available' },
    { value: 'Z2', key: 'awaiting', label: 'On Hold' },
    { value: 'Z3', key: 'sold', label: 'Sold' },
    { value: 'Z0', key: 'blocked', label: 'Booked' }
];

const OTHER = { key: 'other', label: 'Other' };

const STATUS_BY_VALUE = STATUS_CONFIG.reduce((acc, s) => {
    acc[s.value] = s;
    return acc;
}, {});

export default class GetSelectedPropertiesFromProject extends NavigationMixin(LightningElement) {

    @track optionsprojectName = [];
    @track optionstowerName = [];
    @track optionsUnitType = [];

    selectedProjectName;
    selectedTowerName = null;
    selectedUnitType = null;

    @track towers = [];
    collapsedTowers = {};
    @track allUnits = [];
    activeStatus = '';
    searchKey = '';
    density = 'comfortable';
    isLoading = false;
    hasSearched = false;
    selectedUnitId;

    requestSeq = 0;

    objByField = {
        Unit_Type__c: 'Unit__c'
    };

    connectedCallback() {
        this.getAllPicklistValues();
        this.getProjectAndUnitTypePickList();
    }

    getProjectAndUnitTypePickList() {
        getProjectDetails()
            .then(result => {
                this.optionsprojectName = (result || []).map(item => ({
                    label: item.Name,
                    value: item.Name
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Could not load projects: ' + this.reduceError(error), 'error');
            });
    }

    getAllPicklistValues() {
        getPicklistValuesDynamically({ ObjectByField: this.objByField })
            .then(result => {
                const unitTypeValues = result['Unit_Type__c'] || [];
                this.optionsUnitType = this.mapToLabelValuePair(unitTypeValues);
            })
            .catch(error => {
                console.error('error fetching picklist options ===> ', error);
            });
    }

    mapToLabelValuePair(values) {
        return values.map(value => ({
            label: value,
            value: value
        }));
    }

    // ---------- Filter handlers (each change reloads automatically) ----------

    ProjecthandleChange(event) {
        this.selectedProjectName = event.detail.value;
        this.selectedTowerName = null;
        this.optionstowerName = [];
        this.activeStatus = '';
        this.selectedUnitId = null;
        this.collapsedTowers = {};

        if (this.selectedProjectName) {
            getTowersByProject({ projectName: this.selectedProjectName })
                .then(result => {
                    this.optionstowerName = (result || []).map(t => ({
                        label: t,
                        value: t
                    }));
                })
                .catch(error => {
                    console.error('Error loading towers: ', error);
                });
            this.SearchUnits();
        }
    }

    towerHandleChange(event) {
        const value = event.detail.value;
        this.selectedTowerName = value === ALL ? null : value;
        this.SearchUnits();
    }

    unitTypeHandleChange(event) {
        const value = event.detail.value;
        this.selectedUnitType = value === ALL ? null : value;
        this.SearchUnits();
    }

    handleSearchKey(event) {
        this.searchKey = event.target.value || '';
    }

    handleTileClick(event) {
        const key = event.currentTarget.dataset.key;
        this.activeStatus = key === 'all' || this.activeStatus === key ? '' : key;
    }

    clearViewFilters() {
        this.activeStatus = '';
        this.searchKey = '';
    }

    handleDensity(event) {
        this.density = event.currentTarget.dataset.density;
    }

    handleRefresh() {
        this.SearchUnits();
    }

    ClearUnits() {
        this.requestSeq++;
        this.selectedProjectName = null;
        this.selectedTowerName = null;
        this.selectedUnitType = null;
        this.optionstowerName = [];
        this.towers = [];
        this.collapsedTowers = {};
        this.allUnits = [];
        this.activeStatus = '';
        this.searchKey = '';
        this.selectedUnitId = null;
        this.hasSearched = false;
        this.isLoading = false;
    }

    // ---------- Data loading ----------

    SearchUnits() {
        if (!this.selectedProjectName) {
            this.showToast('Error', 'Please select Project', 'error');
            return;
        }

        // Ignore responses from older requests when filters change quickly
        const seq = ++this.requestSeq;
        this.isLoading = true;

        getUnitRecordBasedOnProjectFilter({
            FlatBhkId: this.selectedUnitType,
            projectName: this.selectedProjectName,
            towerName: this.selectedTowerName,
            unitType: this.selectedUnitType
        })
            .then(result => {
                if (seq !== this.requestSeq) {
                    return;
                }
                this.processResult(result);
            })
            .catch(error => {
                if (seq !== this.requestSeq) {
                    return;
                }
                this.towers = [];
                this.allUnits = [];
                this.showToast('Error', 'Could not load units: ' + this.reduceError(error), 'error');
            })
            .finally(() => {
                if (seq === this.requestSeq) {
                    this.isLoading = false;
                    this.hasSearched = true;
                }
            });
    }

    processResult(result) {
        const units = (result && result.getUnitRecordBasedOnProjectList) || [];
        const slabs = (result && result.getSlabsListFromUnit) || [];
        const towerMap = new Map();

        const ensureTower = (code, blockName) => {
            const key = code || blockName || '—';
            if (!towerMap.has(key)) {
                towerMap.set(key, { key, code, blockName, floorMap: new Map() });
            }
            const tower = towerMap.get(key);
            if (!tower.blockName && blockName) {
                tower.blockName = blockName;
            }
            return tower;
        };

        const ensureFloor = (tower, floorNo, floorName) => {
            const key = floorNo != null ? 'F' + floorNo : 'N' + (floorName || '-');
            if (!tower.floorMap.has(key)) {
                tower.floorMap.set(key, { key: tower.key + '|' + key, floorNumber: floorNo, floorName, units: [] });
            }
            return tower.floorMap.get(key);
        };

        // Floors without units still appear so each tower's shape stays intact
        slabs.forEach(s => {
            const block = s.Block__r || {};
            ensureFloor(ensureTower(block.Block__Code__c, null), s.Floor_No__c, s.Name);
        });

        const decorated = units.map(u => this.decorateUnit(u));
        decorated.forEach(u => {
            ensureFloor(ensureTower(u.towerCode, u.blockName), u.floorNo, u.floorName).units.push(u);
        });

        const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });
        const towers = Array.from(towerMap.values()).map(t => {
            const floors = Array.from(t.floorMap.values());
            floors.forEach(f => f.units.sort((a, b) => collator.compare(a.name, b.name)));
            floors.sort((a, b) => {
                if (a.floorNumber == null && b.floorNumber == null) {
                    return collator.compare(a.floorName || '', b.floorName || '');
                }
                if (a.floorNumber == null) return 1;
                if (b.floorNumber == null) return -1;
                return b.floorNumber - a.floorNumber;
            });
            const label = t.blockName || (t.code ? 'Tower ' + t.code : 'Unassigned');
            return {
                key: t.key,
                label,
                code: t.blockName && t.code && t.blockName !== t.code ? t.code : null,
                floors
            };
        });
        towers.sort((a, b) => collator.compare(a.label, b.label));

        this.allUnits = decorated;
        this.towers = towers;

        if (this.selectedUnitId && !decorated.some(u => u.id === this.selectedUnitId)) {
            this.selectedUnitId = null;
        }
    }

    decorateUnit(u) {
        const floor = u.Floor__r || {};
        const block = floor.Block__r || {};
        const cfg = STATUS_BY_VALUE[u.Status__c] || OTHER;
        const name = u.Unit_Name_Code__c || u.Name;
        const tower = block.Name || block.Block__Code__c || '';
        const unit = {
            id: u.Id,
            name,
            recordName: u.Name,
            type: u.Unit_Type__c,
            typeLabel: u.Unit_Type__c || '—',
            status: u.Status__c,
            statusLabel: u.Status__c || 'No status',
            statusKey: cfg.key,
            tower,
            towerCode: block.Block__Code__c,
            blockName: block.Name,
            floorNo: floor.Floor_No__c,
            floorName: floor.Name,
            superBuiltUpArea: u.Super_Built_Up_Area_sq_ft__c,
            basePrice: u.Base_Price_per_sqft__c,
            floorRise: u.Floor_Rise__c,
            premiumCharges: u.Premium_Charges_per_sqft__c,
            infraCharges: u.Infrastructure_Development_Char_pSqft__c,
            facilitiesCharges: u.Facilities_Development_Charges_pSqft__c
        };
        unit.tooltip = [name, unit.type, unit.statusLabel, tower ? 'Tower ' + tower : null]
            .filter(Boolean)
            .join(' • ');
        unit.searchText = [name, u.Name, unit.type, tower, unit.statusLabel]
            .filter(Boolean)
            .join(' ')
            .toLowerCase();
        return unit;
    }

    // ---------- View model ----------

    get statusCounts() {
        const counts = { available: 0, awaiting: 0, sold: 0, blocked: 0, other: 0 };
        this.allUnits.forEach(u => {
            counts[u.statusKey]++;
        });
        return counts;
    }

    get statusTiles() {
        const counts = this.statusCounts;
        const total = this.allUnits.length;
        const pct = n => (total ? Math.round((n / total) * 100) : 0);
        const tile = (key, label, count, pctLabel, barPct) => ({
            key,
            label,
            count,
            pctLabel,
            pressed: String(this.activeStatus === key || (key === 'all' && !this.activeStatus)),
            barStyle: `width:${barPct}%`,
            cssClass: `stat-tile stat-tile_${key}` +
                ((this.activeStatus === key || (key === 'all' && !this.activeStatus)) ? ' is-active' : '')
        });

        const tiles = [tile('all', 'All Units', total, total ? 'Total inventory' : '—', total ? 100 : 0)];
        STATUS_CONFIG.forEach(s => {
            const c = counts[s.key];
            tiles.push(tile(s.key, s.label, c, total ? `${pct(c)}% of total` : '—', pct(c)));
        });
        if (counts.other > 0) {
            tiles.push(tile(OTHER.key, OTHER.label, counts.other, `${pct(counts.other)}% of total`, pct(counts.other)));
        }
        return tiles;
    }

    // Status-mix bar segments for a set of units
    buildSegments(units) {
        const total = units.length;
        return [...STATUS_CONFIG.map(s => s.key), OTHER.key]
            .map(key => {
                const n = units.filter(u => u.statusKey === key).length;
                return {
                    key,
                    n,
                    cssClass: `mix-seg mix-seg_${key}`,
                    style: `width:${total ? (n / total) * 100 : 0}%`
                };
            })
            .filter(s => s.n > 0);
    }

    get visibleTowers() {
        const term = this.searchKey.trim().toLowerCase();
        const filtering = !!(this.activeStatus || term);
        const compact = this.density === 'compact';
        const matches = u => (!this.activeStatus || u.statusKey === this.activeStatus) &&
            (!term || u.searchText.includes(term));

        return this.towers
            .map(t => {
                const towerUnits = [];
                const floors = t.floors
                    .map(f => {
                        towerUnits.push(...f.units);
                        const units = f.units.filter(matches).map(u => ({
                            ...u,
                            cardClass: `unit-card unit-card_${u.statusKey}` +
                                (compact ? ' unit-card_compact' : '') +
                                (u.id === this.selectedUnitId ? ' is-selected' : '')
                        }));
                        const total = f.units.length;
                        const available = f.units.filter(u => u.statusKey === 'available').length;
                        return {
                            key: f.key,
                            label: f.floorNumber != null ? f.floorNumber : (f.floorName || '—'),
                            availabilityLabel: total ? `${available}/${total} available` : 'No units',
                            segments: this.buildSegments(f.units),
                            units,
                            isEmpty: total === 0
                        };
                    })
                    .filter(f => (filtering ? f.units.length > 0 : true));

                const total = towerUnits.length;
                const shown = floors.reduce((sum, f) => sum + f.units.length, 0);
                const floorCount = t.floors.length;
                const counts = { available: 0, awaiting: 0, sold: 0, blocked: 0, other: 0 };
                towerUnits.forEach(u => counts[u.statusKey]++);

                const summary = [
                    `${floorCount} ${floorCount === 1 ? 'floor' : 'floors'}`,
                    filtering ? `${shown} of ${total} units shown` : `${total} ${total === 1 ? 'unit' : 'units'}`
                ].join('  ·  ');

                const stats = [...STATUS_CONFIG, OTHER]
                    .filter(s => counts[s.key] > 0)
                    .map(s => ({
                        key: s.key,
                        text: `${counts[s.key]} ${s.label}`,
                        cssClass: `tower-stat tower-stat_${s.key}`
                    }));

                // Search/status filters always expand towers so matches are never hidden
                const expanded = filtering || !this.collapsedTowers[t.key];
                return {
                    key: t.key,
                    label: t.label,
                    code: t.code,
                    summary,
                    stats,
                    segments: this.buildSegments(towerUnits),
                    floors,
                    total,
                    shown,
                    isExpanded: expanded,
                    ariaExpanded: String(expanded),
                    chevron: expanded ? 'utility:chevrondown' : 'utility:chevronright',
                    toggleLabel: (expanded ? 'Collapse ' : 'Expand ') + t.label
                };
            })
            // Towers with no units for the current filters are hidden entirely
            .filter(t => t.total > 0 && (filtering ? t.shown > 0 : true));
    }

    get visibleUnitCount() {
        return this.visibleTowers.reduce((sum, t) => sum + t.shown, 0);
    }

    get hasMultipleTowers() {
        return this.visibleTowers.length > 1;
    }

    get allCollapsed() {
        const towers = this.visibleTowers;
        return towers.length > 0 && towers.every(t => !t.isExpanded);
    }

    get toggleAllLabel() {
        return this.allCollapsed ? 'Expand all' : 'Collapse all';
    }

    toggleTower(event) {
        const key = event.currentTarget.dataset.key;
        this.collapsedTowers = { ...this.collapsedTowers, [key]: !this.collapsedTowers[key] };
    }

    toggleAllTowers() {
        const collapse = !this.allCollapsed;
        const next = {};
        this.towers.forEach(t => {
            next[t.key] = collapse;
        });
        this.collapsedTowers = next;
    }

    get visibleUnitLabel() {
        const shown = this.visibleUnitCount;
        const total = this.allUnits.length;
        const noun = total === 1 ? 'unit' : 'units';
        return shown === total ? `${total} ${noun}` : `${shown} of ${total} ${noun}`;
    }

    get headerSubtitle() {
        if (!this.selectedProjectName) {
            return 'Browse availability across projects, towers and floors';
        }
        const parts = [
            this.selectedProjectName,
            this.selectedTowerName ? 'Tower ' + this.selectedTowerName : 'All towers',
            this.selectedUnitType || 'All unit types'
        ];
        return parts.join('  ·  ');
    }

    get towerOptionsWithAll() {
        return [{ label: 'All towers', value: ALL }, ...this.optionstowerName];
    }

    get unitTypeOptionsWithAll() {
        return [{ label: 'All unit types', value: ALL }, ...this.optionsUnitType];
    }

    get towerValue() {
        return this.selectedProjectName ? (this.selectedTowerName || ALL) : null;
    }

    get unitTypeValue() {
        return this.selectedProjectName ? (this.selectedUnitType || ALL) : null;
    }

    get isTowerDisabled() {
        return !this.selectedProjectName;
    }

    get isToolbarDisabled() {
        return !this.hasSearched || this.allUnits.length === 0;
    }

    get isRefreshDisabled() {
        return !this.selectedProjectName || this.isLoading;
    }

    get hasActiveFilter() {
        return !!(this.activeStatus || this.searchKey.trim());
    }

    get showStartState() {
        return !this.selectedProjectName && !this.isLoading;
    }

    get showNoResults() {
        return this.hasSearched && !!this.selectedProjectName && !this.isLoading && this.visibleUnitCount === 0;
    }

    get showPlan() {
        return this.hasSearched && !!this.selectedProjectName && this.visibleUnitCount > 0;
    }

    get planClass() {
        return 'plan' + (this.density === 'compact' ? ' plan_compact' : '') + (this.isLoading ? ' is-loading' : '');
    }

    get comfortableVariant() {
        return this.density === 'comfortable' ? 'brand' : 'border-filled';
    }

    get compactVariant() {
        return this.density === 'compact' ? 'brand' : 'border-filled';
    }

    // ---------- Unit drawer ----------

    get selectedUnit() {
        if (!this.selectedUnitId) {
            return null;
        }
        const u = this.allUnits.find(x => x.id === this.selectedUnitId);
        return u ? { ...u, pillClass: `status-pill status-pill_${u.statusKey}` } : null;
    }

    get selectedUnitDetails() {
        const u = this.selectedUnit;
        if (!u) {
            return [];
        }
        const text = (label, value) => ({ label, display: value != null && value !== '' ? value : '—' });
        const num = (label, value, kind) =>
            value != null ? { label, value, isCurrency: kind === 'currency', isArea: kind === 'area' } : text(label, null);
        return [
            text('Unit Type', u.type),
            text('Tower', u.tower),
            text('Floor', u.floorNo != null ? u.floorNo : u.floorName),
            num('Super Built Up Area', u.superBuiltUpArea, 'area'),
            num('Base Price / sq.ft', u.basePrice, 'currency'),
            text('Floor Rise', u.floorRise),
            num('Premium Charges / sq.ft', u.premiumCharges, 'currency'),
            num('Infrastructure Dev. Charges / sq.ft', u.infraCharges, 'currency'),
            num('Facilities Dev. Charges / sq.ft', u.facilitiesCharges, 'currency')
        ];
    }

    handleUnitClick(event) {
        this.selectedUnitId = event.currentTarget.dataset.id;
        // Focus the drawer so Esc closes it
        Promise.resolve().then(() => {
            const drawer = this.template.querySelector('.drawer');
            if (drawer) {
                drawer.focus();
            }
        });
    }

    handleDrawerKey(event) {
        if (event.key === 'Escape') {
            this.closeDrawer();
        }
    }

    closeDrawer() {
        this.selectedUnitId = null;
    }

    openSelectedRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedUnitId,
                objectApiName: 'Unit__c',
                actionName: 'view'
            }
        });
    }

    // ---------- Utils ----------

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (error.body) {
            if (Array.isArray(error.body)) {
                return error.body.map(e => e.message).join(', ');
            }
            if (error.body.message) {
                return error.body.message;
            }
        }
        return error.message || 'Unknown error';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}