package com.retek.alloc.service;

import java.io.Serializable;
import java.math.BigInteger;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.retek.alloc.business.AlcItemSourceList;
import com.retek.alloc.business.AlcItemSourceLocationList;
import com.retek.alloc.business.AlcLocation;
import com.retek.alloc.business.Allocation;
import com.retek.alloc.business.AllocationStatus;
import com.retek.alloc.business.ApprovalData;
import com.retek.alloc.business.ApprovalQuantities;
import com.retek.alloc.business.ApprovalSku;
import com.retek.alloc.business.Code;
import com.retek.alloc.business.PreAllocDetail;
import com.retek.alloc.business.PreAllocHeader;
import com.retek.alloc.business.Source;
import com.retek.alloc.business.XrefAllocDetail;
import com.retek.alloc.business.XrefAllocHeader;
import com.retek.alloc.business.itemsource.AAlcItemSource;
import com.retek.alloc.business.itemsource.AAlcItemSourceList;
import com.retek.alloc.business.itemsource.AlcApprovalQty;
import com.retek.alloc.business.itemsource.AlcItemQty;
import com.retek.alloc.business.itemsource.AlcItemQtyCompositePackStyle;
import com.retek.alloc.business.itemsource.AlcItemQtyCompositeStyle;
import com.retek.alloc.business.itemsource.AlcItemQtyList;
import com.retek.alloc.business.itemsource.AlcItemQtySku;
import com.retek.alloc.business.itemsourcelocation.AlcItemSourceLocation;
import com.retek.alloc.business.itemsourcelocation.AlcItemSourceLocationCalcDetail;
import com.retek.alloc.business.itemsourcelocation.AlcItemSourceLocationKey;
import com.retek.alloc.business.locationgrouplist.ALocationGroupListBuilder;
import com.retek.alloc.business.locationgrouplist.LocationGroupListBuilderFactory;
import com.retek.alloc.business.mhn.MLDPath;
import com.retek.alloc.business.mld.MLDLocation;
import com.retek.alloc.business.mld.PathBuilder;
import com.retek.alloc.calculation.itemsourcelistbuilder.ItemSourceListBuilder;
import com.retek.alloc.calculation.itemsourcelistbuilder.ItemSourceListBuilderFactory;
import com.retek.alloc.db.rms.v11.AStatusDao;
import com.retek.alloc.db.rms.v11.DaoFactory;
import com.retek.alloc.db.rms.v11.WhDao;
import com.retek.alloc.utils.AllocException;
import com.retek.alloc.utils.AllocLogger;
import com.retek.alloc.utils.AllocationProperties;
import com.retek.alloc.utils.RetekDate;
import com.retek.alloc.utils.Severity;
import com.retek.alloc.utils.Utility;
import com.retek.alloc.validators.ValidatorFactory;

public class ApprovalService extends AlcService implements Serializable {
    private static final long serialVersionUID = 4628474050928218883L;
    private static final String STORE_FINAL_QTY = "store_final_qty";

    public void approveNextDestination(Allocation alloc) throws AllocException {
        deleteItemSourceShipSchedule(alloc);

        if (alloc.getMldModifiedLevel().equals(
                AllocationStatus.MLD_TIER_ONE_LEVEL_APPROVAL)) {
            approveNextDestinationNextDestination(alloc);
        } else {
            approveNextDestinationStores(alloc);
        }
    }

    public void approveStores(Allocation alloc) throws AllocException {
        deleteItemSourceShipSchedule(alloc);

        Collection mldPaths;

        List list = null;
        AllocLogger.log(AllocLogger.DEBUG, this, " ANIL in approveStores");
        if (alloc.getRule().isPackDistribution()) {
            list = approvePreScrunchedPackDistribution(alloc);
        } else if (!alloc.isMldAllocation()) {
            AllocLogger.log (AllocLogger.DEBUG, this, " ANIL in approveStores before NONMLD approvePreScrunched");
            mldPaths = buildPathsFromDefaultWarehouse(alloc);
            list = approvePreScrunchedNonMld(alloc, mldPaths, false);
        } else {
            AllocLogger.log (AllocLogger.DEBUG, this, " ANIL in approveStores before approvePreScrunched");
            list = approvePreScrunched(alloc, false);
        }

        List xrefHeaders = scrunch(list);

        writeApproveHeaders(alloc, xrefHeaders);
    }

    public List approvePreScrunched(Allocation alloc, boolean nextDest)
            throws AllocException {
        List xrefList = new ArrayList();
        ApprovalQuantities approvalQuantities = new ApprovalQuantities();

        List locationIds = getLocationIdsForApproval(alloc);

        List approvalSkus = buildItemSourceApprovalSkus(alloc);

        approvalQuantities.buildAllocatedNeed(alloc);
        approvalQuantities.buildApprovalAvailQty(approvalSkus, locationIds);

        Iterator iter = approvalSkus.iterator();

        while (iter.hasNext()) {
            ApprovalSku approvalSku = (ApprovalSku) iter.next();
            xrefList.addAll(processApprovalSku(alloc, approvalSku, locationIds,
                    approvalQuantities, nextDest));
        }
        AllocLogger.log(AllocLogger.DEBUG, this, " ANIL in approvePreScrunched  " + alloc.getAllocationStatus().getStatusLevel() + " is fashin " + alloc.isFashionAllocation());
        if (alloc.isFashionAllocation()) {
            boolean returnVar = getAvailableInventoryError(alloc, xrefList);
            AllocLogger.log(AllocLogger.DEBUG, this, " ANIL in approvePreScrunched  getAvailableInventoryError " + alloc.getAllocationStatus().getStatusLevel() + " is fashin " + alloc.isFashionAllocation() + " returnVar " + returnVar);
            
            if (returnVar == true) {
                ServiceFactory.getApprovalService().deleteXrefAlloc(alloc); // Anil added from bug 13995853.pdf doc
                throw new AllocException(
                        "MLDPath.insufficient_inventory_avaialable",
                        Severity.ERROR, true);
            }
        } else {
            AllocLogger.log(AllocLogger.DEBUG, this, " ANIL APPROVAL SERVICE 222 CURRENT ALLOC STATUS  " + alloc.getAllocationStatus().getStatusLevel()
            + "  alloc.getOriginalAllocationStatus().getStatusLevel() " +  alloc.getOriginalAllocationStatus().getStatusLevel() );
                try{
                     ValidatorFactory.getAvailableInventoryValidator().validate(approvalQuantities);
                   }catch (AllocException ae) {
                            ServiceFactory.getApprovalService().deleteXrefAlloc(alloc);
                     throw ae;
                 }
           
//               if (alloc.getAllocationStatus().getStatusLevel() != AllocationStatus.RESERVED )
//               {
//            ValidatorFactory.getAvailableInventoryValidator().validate(
//                    approvalQuantities);
//               }
        }

        return xrefList;
    }

    protected List approvePreScrunchedNonMld(Allocation alloc,
            Collection mldPaths, boolean nextDest) throws AllocException {
        ApprovalQuantities approvalQuantities = new ApprovalQuantities();
        AllocLogger.log(AllocLogger.DEBUG, this, " ANIL in approvePreScrunchedNonMld  " + alloc.getAllocationStatus().getStatusLevel() 
                  + "  alloc.getOriginalAllocationStatus().getStatusLevel()"  +  alloc.getOriginalAllocationStatus().getStatusLevel() );

        approvalQuantities.setCalculatedAllocatedNeed(alloc
                .getItemSourceLocationList().buildApprovalNeedForItemLocMap());

        return approvePreScrunched(alloc, mldPaths, approvalQuantities,
                nextDest);
    }

    private List approvePreScrunchedNextDest(Allocation alloc)
            throws AllocException {
        Collection mldPaths = alloc.getItemSourceList().getAAlcItemSourceList()
                .buildMLDPaths();
        ApprovalQuantities approvalQuantities = new ApprovalQuantities();

        approvalQuantities.buildApprovalNeedMapNextDest(alloc);

        return approvePreScrunched(alloc, mldPaths, approvalQuantities, true);
    }

    private List approvePreScrunched(Allocation alloc, Collection mldPaths,
            ApprovalQuantities approvalQuantities, boolean nextDest)
            throws AllocException {
        List xrefList = new ArrayList();
        List locationIds = getLocationIdsForApproval(alloc);

        Iterator iter = mldPaths.iterator();

        while (iter.hasNext()) {
            MLDPath mldPath = (MLDPath) iter.next();

            List approvalSkus = buildItemSourceApprovalSkus(alloc, mldPath);

            xrefList.addAll(fulFillApprovalSkus(alloc, approvalSkus, mldPath,
                    locationIds, approvalQuantities, nextDest));
        }
        AllocLogger.log(AllocLogger.DEBUG, this, " ANIL isFashionAllocation " + alloc.getAllocationStatus().getStatusLevel() 
                 + " fashin " + alloc.isFashionAllocation() + "  alloc.getOriginalAllocationStatus().getStatusLevel() " +  alloc.getOriginalAllocationStatus().getStatusLevel() );
        if (alloc.isFashionAllocation()) {

            boolean returnVar = getAvailableInventoryError(alloc, xrefList);
            AllocLogger.log(AllocLogger.DEBUG, this, " ANIL isFashionAllocation getAvailableInventoryError " + alloc.getAllocationStatus().getStatusLevel() + " fashin " + alloc.isFashionAllocation() + " returnVar " + returnVar );
            if (returnVar == true) {
                ServiceFactory.getApprovalService().deleteXrefAlloc(alloc); // Anil added from bug 13995853.pdf doc
                 throw new AllocException(
                        "MLDPath.insufficient_inventory_avaialable",
                        Severity.ERROR, true);
            }
        } else {
        //Anil
            AllocLogger.log(AllocLogger.DEBUG, this, " ANIL APPROVAL SERVICE original status level " + alloc.getAllocationStatus().getOriginalStatusLevel() + " status level  "  
              + alloc.getAllocationStatus().getStatusLevel() + " AllocationStatus.RESERVED " + AllocationStatus.RESERVED +
              " alloc getProcessStatus " + alloc.getProcessStatus() + "  alloc.getOriginalAllocationStatus().getStatusLevel() " +  alloc.getOriginalAllocationStatus().getStatusLevel() );
            try{
                 ValidatorFactory.getAvailableInventoryValidator().validate(approvalQuantities);
               }catch (AllocException ae) {
                        ServiceFactory.getApprovalService().deleteXrefAlloc(alloc);
                 throw ae;
             }
        }

        return xrefList;
    }

    @SuppressWarnings({ "static-access", "rawtypes" })
    protected List approvePreScrunchedPackDistribution(Allocation alloc)
            throws AllocException {
        List<PreAllocHeader> xrefList = buildXrefListForPackDistribution(alloc);

        ApprovalQuantities approvalQuantities = new ApprovalQuantities();
        approvalQuantities.setCalculatedAllocatedNeed(alloc
                .getItemSourceLocationListForPackDistribution()
                .buildApprovalNeedForItemLocMapPackDistribution());
        approvalQuantities.setAvailableQty(alloc
                .getItemSourceLocationListForPackDistribution()
                .buildAvailableQuantityMapForPackDistribution());
          // Anil 13995853.pdf
          try{
               ValidatorFactory.getAvailableInventoryPackDistributionValidator().validate(approvalQuantities);
           }catch (AllocException ae) {
                 ServiceFactory.getApprovalService().deleteXrefAlloc(alloc);
                 throw ae;
           }
    //    ValidatorFactory.getAvailableInventoryPackDistributionValidator()
    //            .validate(approvalQuantities);

        return xrefList;
    }

    private boolean getAvailableInventoryError(Allocation alloc, List xrefList)
            throws AllocException {
        double totalAvail = 0.0;
        double totalHoldBack = 0.0;
        double totalAllocated = 0.0;
        boolean returnVar = true;

        Map packQty = new HashMap();

        if (alloc.getItemSourceList() != null) {
            AlcItemSourceList itemSourcesToAllocate = (AlcItemSourceList) alloc
                    .getItemSourceList();
            for (int i = 0; i < itemSourcesToAllocate.size(); i++) {
                AAlcItemSource ItemSource = (AAlcItemSource) itemSourcesToAllocate
                        .get(i);
                totalAvail += ItemSource.getAvailQty();
                if (!ItemSource.isHoldBackPctFlag()) {
                    totalHoldBack += ItemSource.getHoldBackValue();
                } else {
                    totalHoldBack += ItemSource.getAvailQty()
                            * ItemSource.getHoldBackValue() / 100.0;
                }

                // For Non-sellable Fashion Complex Pack
                if (alloc.hasNonSellableFashionPack()) {
                    AlcItemQtyCompositeStyle itemQty = (AlcItemQtyCompositeStyle) ItemSource
                            .getAlcItemQty();
                    Iterator componentIter = itemQty.getAlcItemQtys()
                            .iterator();
                    while (componentIter.hasNext()) {
                        AlcItemQty component = (AlcItemQty) componentIter
                                .next();
                        if (component instanceof AlcItemQtyCompositePackStyle) {
                            int packSize = 0;
                            AlcItemQtyCompositePackStyle pItemQty = (AlcItemQtyCompositePackStyle) component;
                            // Code to be put in place to create a map named
                            // packQty containing pack
                            // as the
                            // key and sum of sku qty as the value so that the
                            // same can be used
                            // outside
                            // e.g. If there are 2 Fashion Sources having a
                            // packs
                            // Pack 1 having sku1-2 and sku2-3 qty ie total 5
                            // so we will put pack no as key and 5 as value in
                            // the map above.
                            Iterator compIter = pItemQty.getAlcItemQtys()
                                    .iterator();
                            while (compIter.hasNext()) {

                                AlcItemQtySku componentSku = (AlcItemQtySku) compIter
                                        .next();
                                packSize += (int) componentSku.getAvailQty();

                            }
                            packQty.put(component.getItem().getItemKey()
                                    .getItemId(), new Integer(packSize));
                        }
                    }
                }
            }
        }

        if (!alloc.isMldAllocation()) {
            if (xrefList != null && xrefList.size() > 0) {
                Iterator xrefIterator = xrefList.iterator();
                while (xrefIterator.hasNext()) {
                    PreAllocHeader p = (PreAllocHeader) xrefIterator.next();
                    if (packQty.containsKey(p.getItemId())) {
                        int packSize = ((Integer) packQty.get(p.getItemId()))
                                .intValue();
                        // Multiply allocated qty by pack size as here allocated
                        // quantity which
                        // comes here is number of packs(not the skus)
                        totalAllocated += (p.getPreAllocDetail()
                                .getQtyAllocated()) * (packSize);
                    } else {
                        totalAllocated += p.getPreAllocDetail()
                                .getQtyAllocated();
                    }
                }
            }
        } else {
            if (xrefList != null && xrefList.size() > 0) {
                Iterator xrefIterator = xrefList.iterator();
                boolean mldStoreLevelApproval = false;
                if (AllocationStatus.MLD_STORE_LEVEL_APPROVAL
                        .equalsIgnoreCase(alloc.getAllocationStatus()
                                .getMldApprovalLevel())) {
                    mldStoreLevelApproval = true;
                }
                while (xrefIterator.hasNext()) {
                    PreAllocHeader p = (PreAllocHeader) xrefIterator.next();
                    // For approval at store level
                    if (mldStoreLevelApproval
                            && "S".equalsIgnoreCase(p.getPreAllocDetail()
                                    .getToLocType())) {
                        if (packQty.containsKey(p.getItemId())) {
                            int packSize = ((Integer) packQty
                                    .get(p.getItemId())).intValue();
                            // Multiply allocated qty by pack size as here
                            // allocated quantity which
                            // comes here is number of packs(not the skus)
                            totalAllocated += (p.getPreAllocDetail()
                                    .getQtyAllocated()) * (packSize);
                        } else {
                            totalAllocated += p.getPreAllocDetail()
                                    .getQtyAllocated();
                        }
                    }// For Approval at next destination
                    else if (!mldStoreLevelApproval
                            && "W".equalsIgnoreCase(p.getPreAllocDetail()
                                    .getToLocType())) {
                        if (packQty.containsKey(p.getItemId())) {
                            int packSize = ((Integer) packQty
                                    .get(p.getItemId())).intValue();
                            // Multiply allocated qty by pack size as here
                            // allocated quantity which
                            // comes here is number of packs(not the skus)
                            totalAllocated += (p.getPreAllocDetail()
                                    .getQtyAllocated()) * (packSize);
                        } else {
                            totalAllocated += p.getPreAllocDetail()
                                    .getQtyAllocated();
                        }
                    }
                }
            }
        }

        if ((totalAvail - totalHoldBack) - (totalAllocated) >= 0) {
            returnVar = false;
        }
        return returnVar;
    }

    private void approveNextDestinationNextDestination(Allocation alloc)
            throws AllocException {
        List preScrunched = approvePreScrunchedNextDest(alloc);

        if (preScrunched.size() > 0) {
            List scrunchedXrefHeaders = scrunch(preScrunched);

            List tierOneScrunched = removeNonTierOne(alloc,
                    scrunchedXrefHeaders);

            adjustForSOM(alloc, tierOneScrunched);

            writeApproveHeaders(alloc, tierOneScrunched);
        } else {
            throw new AllocException("ApprovalService.noPrescrunchRecords",
                    Severity.ERROR);
        }
    }

    private void approveNextDestinationStores(Allocation alloc)
            throws AllocException {
        List list = approvePreScrunched(alloc, false);

        List xrefHeaders = scrunch(list);

        List nextDestinationXrefHeaders = removeNonNextDestinationXrefAllocHeaders(
                alloc, xrefHeaders);

        if (nextDestinationXrefHeaders.size() > 0) {
            writeApproveHeaders(alloc, nextDestinationXrefHeaders);
        } else {
            throw new AllocException("ApprovalService.noPrescrunchRecords",
                    Severity.ERROR);
        }
    }

    private void buildApprovalAvailQty(List approvalSkus, List locationIds,
            Map approvalAvailQtyMap) throws AllocException {
        Iterator iter = approvalSkus.iterator();
        while (iter.hasNext()) {
            ApprovalSku approvalSku = (ApprovalSku) iter.next();
            MLDPath mldPath = approvalSku.getItemSource().getMldPath();
            MLDPath filteredPath = mldPath.getFilteredPath(
                    approvalSku.getWhId(), locationIds);
            String key = approvalSku.buildItemSourceLocationKey();
            MLDPath trimmedPathThread = filteredPath.getTrimmedThread(key);
            trimmedPathThread.populateApprovalAvailQty(approvalSku,
                    approvalAvailQtyMap);
        }
    }

    public List processApprovalSku(Allocation alloc, ApprovalSku approvalSku,
            List locationIds, ApprovalQuantities approvalQuantities,
            boolean nextDest) throws AllocException {
        List xrefList = new ArrayList();

        MLDPath mldPath = approvalSku.getItemSource().getMldPath();

        // filter per item source and locations
        MLDPath filteredPath = mldPath.getFilteredPath(approvalSku.getWhId(),
                locationIds);

        String key = approvalSku.buildItemSourceLocationKey();

        // filter per itemSource for specific itemLocs
        MLDPath trimmedPathThread = filteredPath.getTrimmedThread(key);

        // locations/stores to approve to
        List mldLocationsOrdered = null;
        if (nextDest) {
            mldLocationsOrdered = filteredPath
                    .getTierOrderedLocations(approvalSku);
        } else {
            mldLocationsOrdered = filteredPath.getTierOrderedStores();
        }

        xrefList.addAll(startFulFillingStores(alloc, mldLocationsOrdered,
                approvalSku, trimmedPathThread, approvalQuantities, nextDest));

        return xrefList;
    }

    public List fulFillApprovalSkus(Allocation alloc, List approvalSkus,
            MLDPath mldPath, List locationIds,
            ApprovalQuantities approvalQuantities, boolean nextDest)
            throws AllocException {
        List xrefList = new ArrayList();

        for (int i = 0; i < approvalSkus.size(); i++) {
            ApprovalSku approvalSku = (ApprovalSku) approvalSkus.get(i);

            // filter per item source and locations
            MLDPath filteredPath = mldPath.getFilteredPath(
                    approvalSku.getWhId(), locationIds);

            String key = approvalSku.buildItemSourceLocationKey();

            // filter per itemSource for specific itemLocs
            MLDPath trimmedPathThread = filteredPath.getTrimmedThread(key);

            trimmedPathThread.populateApprovalAvailQty(approvalSku,
                    approvalQuantities.getAvailableQty());

            // locations/stores to approve to
            List mldLocationsOrdered = null;

            if (nextDest) {
                mldLocationsOrdered = filteredPath
                        .getTierOrderedLocations(approvalSku);
            } else {
                mldLocationsOrdered = filteredPath.getTierOrderedStores();
            }

            xrefList.addAll(startFulFillingStores(alloc, mldLocationsOrdered,
                    approvalSku, trimmedPathThread, approvalQuantities,
                    nextDest));
        }
        return xrefList;
    }

    private List startFulFillingStores(Allocation alloc,
            List mldStoreLocations, ApprovalSku approvalSku,
            MLDPath filteredPath, ApprovalQuantities approvalQuantities,
            boolean nextDest) throws AllocException {
        List xrefList = new ArrayList();

        for (int i = 0; i < mldStoreLocations.size(); i++) {
            MLDLocation requestingLocation = (MLDLocation) mldStoreLocations
                    .get(i);
            MLDLocation fulFillingLocation = filteredPath
                    .getMldLocation(requestingLocation.getParentLocationId());

            int approvalNeed = approvalQuantities.getNeedForItemLoc(
                    approvalSku, requestingLocation);

            if (approvalNeed > 0) {
                approvalQuantities.getAvailableQty().put(STORE_FINAL_QTY,
                        new Integer(approvalNeed));
                xrefList.addAll(fulFill(alloc, requestingLocation,
                        fulFillingLocation, filteredPath, approvalQuantities,
                        approvalSku, nextDest));
            }
        }
        return xrefList;
    }

    private int getNeedForItemLoc(Allocation alloc, ApprovalSku approvalSku,
            MLDLocation requestingLocation, Map approvalNeedMap) {
        int needSum = 0;

        String itemLockey = requestingLocation.getLocationId() + ":"
                + approvalSku.getItemId() + ":" + approvalSku.getOrderNo();

        BigInteger temp = (BigInteger) approvalNeedMap.get(itemLockey);

        if (temp != null) {
            needSum = temp.intValue();
        }

        return needSum;
    }

    private List fulFill(Allocation alloc, MLDLocation requestingLocation,
            MLDLocation fulFillingLocation, MLDPath filteredPath,
            ApprovalQuantities approvalQuantities, ApprovalSku approvalSku,
            boolean nextDest) throws AllocException {
        List xrefList = new ArrayList();

        Integer approvalNeed = (Integer) approvalQuantities.getAvailableQty()
                .get(STORE_FINAL_QTY);

        boolean continueFulFilling = true;

        if (fulFillingLocation == null || approvalNeed == null
                || approvalNeed.intValue() == 0) { // exit
                                                   // condition
            continueFulFilling = false;
        }

        if (continueFulFilling) {
            String key = approvalSku.buildKey(approvalSku,
                    fulFillingLocation.getLocationId());
            ApprovalData approvalData = (ApprovalData) approvalQuantities
                    .getAvailableQty().get(key);
            if (approvalData == null) {
                key = approvalSku.buildKeyMidTier(approvalSku,
                        fulFillingLocation.getLocationId());
                approvalData = (ApprovalData) approvalQuantities
                        .getAvailableQty().get(key);
            }

            int fulFillerSoh = (int) approvalData.getSoh();
            Map adjustingValue = new HashMap();
            adjustingValue.put("key", null);

            // enough to completly fulFill stores need
            if (fulFillerSoh >= approvalNeed.intValue()) {
                xrefList.addAll(createPreAllocHeadersForMidTier(alloc,
                        requestingLocation, fulFillingLocation, approvalSku,
                        approvalNeed.intValue(), filteredPath,
                        approvalQuantities, nextDest));
                // used some of the SOH
                approvalData.setSoh(fulFillerSoh
                        - approvalQuantities.getCurrentSomAdjustmentQty());
                // lower the approval need
                approvalQuantities.adjustAppprovalNeed(requestingLocation,
                        approvalSku, approvalNeed.intValue());
                // storeNeed completly met
                approvalNeed = new Integer(0);
                approvalQuantities.getAvailableQty().put(STORE_FINAL_QTY,
                        approvalNeed);
            }
            // not enough to fulFill
            else {
                // some to fulFill, but not enough for stores need
                if (fulFillerSoh > 0) { // use what it has
                    xrefList.addAll(createPreAllocHeadersForMidTier(alloc,
                            requestingLocation, fulFillingLocation,
                            approvalSku, fulFillerSoh, filteredPath,
                            approvalQuantities, nextDest));

                    // fulFiller soh all used up
                    approvalData.setSoh(0.0);
                    // store stil has need
                    approvalNeed = new Integer(approvalNeed.intValue()
                            - approvalQuantities.getCurrentSomAdjustmentQty());
                    // lower the approval need
                    approvalQuantities.adjustAppprovalNeed(requestingLocation,
                            approvalSku, fulFillerSoh);
                }

                approvalQuantities.getAvailableQty().put(STORE_FINAL_QTY,
                        approvalNeed);

                approvalData.setNowFromAbove(true);

                // now go up the chain to find more qty
                MLDLocation fulFillerParent = filteredPath
                        .getMldLocation(fulFillingLocation
                                .getParentLocationId());
                xrefList.addAll(fulFill(alloc, requestingLocation,
                        fulFillerParent, filteredPath, approvalQuantities,
                        approvalSku, nextDest));
            }
        }
        return xrefList;
    }

    private void adjustOnHand(Map approvalAvailQtyMap,
            MLDLocation requestingLocation, ApprovalSku approvalSku,
            int fulFillerSoh) {
        String key = approvalSku.buildKey(approvalSku,
                requestingLocation.getLocationId());

        BigInteger onHand = (BigInteger) approvalAvailQtyMap.get(key);

        int newOnHand = onHand.intValue() - fulFillerSoh;

        approvalAvailQtyMap.put(key, new BigInteger("" + newOnHand));
    }

    private void adjustAppprovalNeed(Map approvalNeedMap,
            MLDLocation requestingLocation, ApprovalSku approvalSku,
            int usedNeed) {
        String itemLockey = requestingLocation.getLocationId() + ":"
                + approvalSku.getItemId() + ":" + approvalSku.getOrderNo();

        BigInteger need = (BigInteger) approvalNeedMap.get(itemLockey);

        int newNeed = need.intValue() - usedNeed;

        approvalNeedMap.put(itemLockey, new BigInteger("" + newNeed));
    }

    protected List buildItemSourceApprovalSkus(Allocation alloc, MLDPath mldPath)
            throws AllocException {
        List itemApprovalSkus = new ArrayList();

        ItemSourceListBuilder listBuilder = ItemSourceListBuilderFactory
                .createItemSourceListBuilder(alloc);

        List seperatedByReleaseDateAndWh = listBuilder
                .buildItemSourceLists(alloc.getItemSourceList()
                        .getAAlcItemSourceList());

        List itemSourceListOfLists = listBuilder
                .sortLists(seperatedByReleaseDateAndWh);

        Iterator itemSourceListsIter = itemSourceListOfLists.iterator();

        int approvalSkuSeq = 0;
        while (itemSourceListsIter.hasNext()) {
            AAlcItemSourceList itemSourcesList = (AAlcItemSourceList) itemSourceListsIter
                    .next();

            List itemSources = itemSourcesList
                    .getItemSourcesPerMLDPath(mldPath);
            // List itemSources = itemSourcesList.getAlcItemSources();

            for (int i = 0; i < itemSources.size(); i++) {
                AAlcItemSource itemSource = (AAlcItemSource) itemSources.get(i);

                List newSkus = new ArrayList();

                // AlcApprovalQtys which are child of a ASN or BOL ItemSource
                List approvalQtys = itemSource.getApprovalQtys();
                if (approvalQtys != null && approvalQtys.size() > 0) {
                    itemApprovalSkus
                            .addAll(buildApprovalSkusFromAlcApprovalQty(
                                    itemSource, approvalSkuSeq));
                } else {
                    itemApprovalSkus.addAll(buildApprovalSkusFromItemQtySkus(
                            itemSource,
                            itemSource.getAlcItemQtyAllocatedSkus(),
                            approvalSkuSeq));
                }
                approvalSkuSeq++;
            }
        }

        return itemApprovalSkus;
    }

    private List buildItemSourceApprovalSkus(Allocation alloc)
            throws AllocException {
        List itemApprovalSkus = new ArrayList();

        AAlcItemSourceList itemSourcesList = alloc.getItemSourceList()
                .getAAlcItemSourceList().getOrderedListBySource(true);

        List itemSources = itemSourcesList.getAlcItemSources();

        int approvalSkuSeq = itemSources.size();
        for (int i = 0; i < itemSources.size(); i++) {
            AAlcItemSource itemSource = (AAlcItemSource) itemSources.get(i);

            List newSkus = new ArrayList();

            // AlcApprovalQtys which are child of a ASN or BOL ItemSource
            List approvalQtys = itemSource.getApprovalQtys();
            if (approvalQtys != null && approvalQtys.size() > 0) {
                itemApprovalSkus.addAll(buildApprovalSkusFromAlcApprovalQty(
                        itemSource, approvalSkuSeq));
            } else {
                itemApprovalSkus.addAll(buildApprovalSkusFromItemQtySkus(
                        itemSource, itemSource.getAlcItemQtyAllocatedSkus(),
                        approvalSkuSeq));
            }
            approvalSkuSeq--;

        }

        return itemApprovalSkus;
    }

    private Map buildApprovalNeedMapNextDest(Allocation alloc)
            throws AllocException {
        ALocationGroupListBuilder builder = LocationGroupListBuilderFactory
                .createBuilder(alloc);
        List alcLocations = builder.buildGroupList(alloc.getItemSourceList()
                .getAAlcItemSourceList());
        List locationIds = convertAlcLocationToIds(alcLocations);
        Map map = new HashMap();
        Iterator iter = alloc.getItemSourceList().getAAlcItemSourceList()
                .iterator();
        while (iter.hasNext()) {
            AAlcItemSource itemSource = (AAlcItemSource) iter.next();
            MLDPath fatPath = itemSource.getMldPath();
            MLDPath filterPath = fatPath.getFilteredPath(
                    itemSource.getWarehouseNo(), locationIds);
            MLDLocation itemSourceMldLocation = filterPath
                    .getMldLocation(itemSource.getWarehouseNo());
            Iterator nextDestMldLocationIter = itemSourceMldLocation
                    .getMldLocations().values().iterator();
            while (nextDestMldLocationIter.hasNext()) {
                MLDLocation mldLocation = (MLDLocation) nextDestMldLocationIter
                        .next();
                map.putAll(mldLocation.getAlcItemSourceLocationList()
                        .buildNeedForItemLocMapForNextDestination());
            }
        }

        return map;
    }

    private List convertAlcLocationToIds(List alcLocations) {
        List list = new ArrayList();
        Iterator iter = alcLocations.iterator();
        while (iter.hasNext()) {
            AlcLocation loc = (AlcLocation) iter.next();
            list.add(loc.getLocationId());
        }
        return list;
    }

    public List removeNonTierOne(Allocation alloc, List xrefHeaders)
            throws AllocException {
        Map map = convertXrefHeadersToMap(xrefHeaders);
        List newList = new ArrayList();

        List approvalSkus = null;

        Iterator iter = alloc.getItemSourceList().getAAlcItemSourceList()
                .buildMLDPaths().iterator();
        while (iter.hasNext()) {
            MLDPath mldPath = (MLDPath) iter.next();

            approvalSkus = buildItemSourceApprovalSkus(alloc, mldPath);

            for (int i = 0; i < approvalSkus.size(); i++) {
                ApprovalSku approvalSku = (ApprovalSku) approvalSkus.get(i);

                String key = buildHeaderKey(approvalSku.getItemId(),
                        approvalSku.getWhId(), approvalSku.getOrderNo());
                XrefAllocHeader header = (XrefAllocHeader) map.get(key);
                if (header != null) {
                    newList.add(header);
                }
            }
        }

        return newList;
    }

    public void writeApproveHeaders(Allocation alloc, List xrefHeaders)
            throws AllocException {
        AStatusDao sb = DaoFactory.getAStatusDaoInstance();
        Connection conn = null;
        try {
            conn = getConnection();

            if (conn.getAutoCommit() == true)
                conn.setAutoCommit(false);

            sb.setConnection(conn);
            sb.setStatus(alloc.getAllocationStatus());

            sb.setAllocId(alloc.getId());

            sb.insertXrefAllocNew(xrefHeaders);
            sb.updateAlcAllocStatus();
            if (alloc.getAllocationStatus().getStatusLevel() == AllocationStatus.APPROVED) {
                alloc.setIsApproveSuccess(true);
                deleteXrefAlloc(alloc);
                alloc.setIsApproveSuccess(false);
            }

            if (conn.getAutoCommit() == false)
                conn.commit();
        } catch (SQLException e) {
            try {
                if (conn.getAutoCommit() == false)
                    conn.rollback();
            } catch (SQLException e1) {
                // ignore this
            }

            throw new AllocException("StatusBean.approval_header_write_failed",
                    e);
        } finally {
            releaseConnection(conn);
        }
    }

    private List buildApprovalSkusFromAlcApprovalQty(AAlcItemSource itemSource,
            int approvalSkuSeq) {
        List approvalSkus = new ArrayList();
        String availQty = null;
        String itemId = null;

        List approvalQtys = itemSource.getApprovalQtys();
        AlcItemQtyList alcItemSourceQtySkus = itemSource
                .getAlcItemQtyAllocatedSkus();
        HashMap hmAvailQty = new HashMap();
        for (int i = 0; i < alcItemSourceQtySkus.size(); i++) {
            AlcItemQty itemQty = (AlcItemQty) alcItemSourceQtySkus.get(i);
            hmAvailQty.put((Object) itemQty.getItemId(),
                    (Object) String.valueOf(itemQty.getAvailQty()));
        }

        for (int i = 0; i < approvalQtys.size(); i++) {
            AlcApprovalQty approvalQty = (AlcApprovalQty) approvalQtys.get(i);
            itemId = approvalQty.getItemKey().getItemId();
            if ((itemId != null) && (hmAvailQty.containsKey(itemId))) {
                availQty = hmAvailQty.get(itemId).toString();
                if (availQty != null)
                    approvalQty.setAvailableQty(Double.parseDouble(availQty));
            }
            approvalSkus.add(new ApprovalSku(itemSource, approvalQty,
                    approvalSkuSeq));
        }

        return approvalSkus;
    }

    private List buildApprovalSkusFromItemQtySkus(AAlcItemSource itemSource,
            AlcItemQtyList alcItemSourceQtySkus, int approvalSkuSeq) {
        List approvalSkus = new ArrayList();

        for (int i = 0; i < alcItemSourceQtySkus.size(); i++) {
            AlcItemQty itemQty = (AlcItemQty) alcItemSourceQtySkus.get(i);
            approvalSkus.add(new ApprovalSku(itemSource, itemQty,
                    approvalSkuSeq));
        }

        return approvalSkus;
    }

    private List createPreAllocHeadersForMidTier(Allocation alloc,
            MLDLocation requestingLocation, MLDLocation fulFillingLocation,
            ApprovalSku approvalSku, int qty, MLDPath filteredPath,
            ApprovalQuantities approvalQuantities, boolean nextDest)
            throws AllocException {
        List headers = new ArrayList();

        List destinationLocationIds = new ArrayList();
        destinationLocationIds.add(requestingLocation.getLocationId());
        MLDPath path = filteredPath.getFilteredPath(
                fulFillingLocation.getLocationId(), destinationLocationIds);

        List list = path.getTierOrderedLocationsDesc();
        Iterator iter = list.iterator();

        while (iter.hasNext()) {
            MLDLocation childLoc = null;
            MLDLocation parentLoc = null;

            if (nextDest) {
                parentLoc = (MLDLocation) iter.next();
                childLoc = requestingLocation;
            } else {
                childLoc = (MLDLocation) iter.next();
                parentLoc = filteredPath.getMldLocation(childLoc
                        .getParentLocationId());
            }

            if (parentLoc != null) {
                int adjustedApprovalQty = adjustedApprovalQty = adjustForSom(
                        qty, parentLoc, approvalSku);

                approvalQuantities
                        .updateCurrentSomQty(qty, adjustedApprovalQty);

                int parentTierNumber = filteredPath
                        .getTierLevelForLocationId(parentLoc.getLocationId());

                String key = approvalSku.buildKey(approvalSku,
                        parentLoc.getLocationId());
                ApprovalData approvalData = (ApprovalData) approvalQuantities
                        .getAvailableQty().get(key);

                if (approvalData == null) {
                    key = approvalSku.buildKeyMidTier(approvalSku,
                            parentLoc.getLocationId());
                    approvalData = (ApprovalData) approvalQuantities
                            .getAvailableQty().get(key);
                }

                if (approvalData != null) {
                    headers.add(createPreAllocHeader(alloc, childLoc,
                            parentLoc, approvalSku, adjustedApprovalQty,
                            approvalData, parentTierNumber,
                            approvalQuantities.getAvailableQty()));
                }
            }

        }
        return headers;
    }

    private PreAllocHeader createPreAllocHeader(Allocation alloc,
            MLDLocation requestingLocation, MLDLocation fulFillingLocation,
            ApprovalSku approvalSku, int qty, ApprovalData approvalData,
            int parentTierNumber, Map approvalAvailQtyMap)
            throws AllocException {
        PreAllocDetail detail = new PreAllocDetail();

        detail.setQtyAllocated(qty);

        AlcItemSourceLocation itemLoc = getItemLocFromMLDLocation(requestingLocation);
        detail.setInStoreDate(itemLoc.getInStoreRetekDate());

        detail.setRushFlag(getItemLocFromMLDLocation(requestingLocation)
                .isRushFlag());

        detail.setToLoc(requestingLocation.getLocationId());
        detail.setToLocType(requestingLocation.isStore() ? "S" : "W");

        PreAllocHeader header = new PreAllocHeader();
        header.setPreAllocDetail(detail);
        header.setApprovalSkuSeq(approvalSku.getApprovalSkuSeq());

        RetekDate releaseDate = null;
        if (alloc.isMldAllocation()
                && AllocationProperties.getHandle().getDistributionLevel() == PathBuilder.DISTRIBUTION_LEVEL_MLD_SHIP_SCHEDULE) {
            releaseDate = fulFillingLocation
                    .getDepartureDateForLocation(requestingLocation
                            .getLocationId());
            if (!approvalData.isNowFromAbove()) {
                releaseDate = approvalData.getReleaseDate();
            }
        } else {
            releaseDate = approvalData.getReleaseDate();
        }
        header.setReleaseDate(releaseDate);

        header.setAlcAllocId(alloc.getId());
        header.setAllocDesc(alloc.getDescription());

        header.setParentTierNumber(parentTierNumber);

        header.setCommentDesc(alloc.getComments());

        if (alloc.getContext() != null) {
            header.setContextType(alloc.getContext().getId());
            //Added the code to insert promo # in case Promotion is chosen from context dropdown	 
            if(alloc.getContext().getId().equalsIgnoreCase(Code.CODE_PROMOTION)){
         		header.setContextValue(alloc.getPromotion().getId());
         	}else{
         		header.setContextValue(alloc.getContext().getDescription());
       	     }
        }

        header.setAggregateDiffId(approvalSku.getAggregateDiffId());

        String headerParentKey = null;
        String headerChildKey = null;

        String childOrderNo = "";
        String parentOrderNo = "";

        if (approvalSku.getSourceType() == Source.WAREHOUSE) {

            if (approvalData.isNowFromAbove()) {
                header.setOrderType("PREDIST");
            }
        } else {
            if (approvalData.isNowFromAbove()) {
                header.setOrderType("PREDIST");
            }

            if (approvalData.isProductSource()) {
                header.setOrderType("PREDIST");
                header.setDoc(approvalSku.getOrderNo());
                header.setDocType(getDocType(approvalSku.getSourceType()));
                headerParentKey = approvalSku.getOrderNo();
            }
        }

        if (headerParentKey == null) {
            String parentLocId = null;
            String parentOrderType = header.getOrderType();

            if (fulFillingLocation.getParentLocationId() == null) {
                parentLocId = fulFillingLocation.getLocationId();
            } else {
                parentLocId = fulFillingLocation.getParentLocationId();
            }

            String satisfingLocationId = findAncestorSoh(approvalSku,
                    fulFillingLocation, approvalAvailQtyMap);
            if (!approvalSku.getWhId().equals(satisfingLocationId)) {
                parentOrderNo = satisfingLocationId;
            } else {
                if (approvalSku.getOrderNo() != null) {
                    parentOrderNo = approvalSku.getOrderNo();
                } else {
                    parentOrderNo = approvalSku.getWhId();
                }
            }

            if (fulFillingLocation.getLocationId().equals(parentOrderNo)
                    || parentOrderNo.equals(parentLocId)) {
                parentOrderType = "";
            }

            headerParentKey = approvalSku.getItemId() + ":" + parentLocId + ":"
                    + approvalSku.getApprovalSkuSeq() + ":" + parentOrderType
                    + ":" + parentOrderNo + ":" + approvalSku.getChildOrderNo();
        }

        if (approvalSku.getSourceType() == Source.WAREHOUSE) {
            childOrderNo = parentOrderNo;
        } else {
            if (parentOrderNo != null && !parentOrderNo.equals("")) {
                childOrderNo = parentOrderNo;
            } else {
                childOrderNo = header.getDoc();
            }
        }

        headerChildKey = approvalSku.getItemId() + ":"
                + fulFillingLocation.getLocationId() + ":"
                + approvalSku.getApprovalSkuSeq() + ":" + header.getOrderType()
                + ":" + childOrderNo + ":" + approvalSku.getChildOrderNo();

        header.setXrefAllocNo(headerChildKey);
        header.setOrderNo(headerParentKey);

        header.setItemId(approvalSku.getItemId());
        header.setStatus("" + alloc.getAllocationStatus().getStatusLevel());
        header.setWhId(fulFillingLocation.getLocationId());

        if (header.getDocType() != null
                && (header.getDocType().equals(Source.ASN_STRING) || header
                        .getDocType().equals(Source.BOL_STRING))
                && approvalSku.getChildOrderNo() != null) {
            header.setChildOrderNo(approvalSku.getChildOrderNo());
        }

        return header;
    }

    protected PreAllocHeader createPreAllocHeaderPackDistribution(
            Allocation allocation, AlcItemSourceLocation alcItemSourceLocation,
            int approvalSkuSequence) throws AllocException {
        PreAllocDetail detail = new PreAllocDetail();
        AlcItemSourceLocationCalcDetail calcDetails = (AlcItemSourceLocationCalcDetail) alcItemSourceLocation
                .getCalcDetails().get(0);
        detail.setQtyAllocated(calcDetails.getFinalAllocatedQty());
        detail.setInStoreDate(alcItemSourceLocation.getInStoreRetekDate());
        detail.setToLoc(alcItemSourceLocation.getLocationId());
        detail.setToLocType("S");

        PreAllocHeader header = new PreAllocHeader();
        header.setPreAllocDetail(detail);
        header.setApprovalSkuSeq(approvalSkuSequence);
        header.setReleaseDate(alcItemSourceLocation.getReleaseDate());
        header.setAlcAllocId(allocation.getId());
        header.setAllocDesc(allocation.getDescription());
        // header.setParentTierNumber(parentTierNumber);
        header.setCommentDesc(allocation.getComments());

        if (allocation.getContext() != null) {
            header.setContextType(allocation.getContext().getId());
            header.setContextValue(allocation.getContext().getDescription());
        }

        String headerParentKey = null;
        String headerChildKey = null;

        String childOrderNo = "";
        String parentOrderNo = "";

        header.setOrderType("PREDIST");
        header.setDoc(alcItemSourceLocation.getOrderNo());
        // header.setDocType(alcItemSourceLocation.getItemSource().getSourceType());
        headerParentKey = alcItemSourceLocation.getOrderNo();

        if (headerParentKey == null) {
            //String parentLocId = header.getWhId();
            //String parentOrderType = header.getOrderType();

            headerParentKey = alcItemSourceLocation.getItemId() + ":"
                    + alcItemSourceLocation.getWhId() + ":"
                    + alcItemSourceLocation.getOrderNo();
        }

        headerChildKey = alcItemSourceLocation.getItemId() + ":"
                + alcItemSourceLocation.getWhId() + ":"
                + alcItemSourceLocation.getOrderNo();

        header.setXrefAllocNo(headerChildKey);
        header.setOrderNo(headerParentKey);

        header.setItemId(alcItemSourceLocation.getItemId());
        header.setStatus("" + allocation.getAllocationStatus().getStatusLevel());
        header.setWhId(alcItemSourceLocation.getWhId());

        return header;
    }

    private String findAncestorSoh(ApprovalSku approvalSku,
            MLDLocation fulFillingLocation, Map approvalAvailQtyMap)
            throws AllocException {
        String parentOrderNo = "";
        String key = approvalSku.buildKeyMidTier(approvalSku,
                fulFillingLocation.getLocationId());

        ApprovalData approvalData = (ApprovalData) approvalAvailQtyMap.get(key);

        if (approvalData == null) {
            key = approvalSku.buildKey(approvalSku,
                    fulFillingLocation.getLocationId());
            approvalData = (ApprovalData) approvalAvailQtyMap.get(key);
        }

        if (approvalData != null && approvalData.getSoh() > 0) {
            parentOrderNo = fulFillingLocation.getLocationId();
        }

        if (parentOrderNo.equals("")) {
            MLDLocation parentLocation = getParentLocation(approvalSku,
                    fulFillingLocation);
            if (parentLocation != null) {
                parentOrderNo = findAncestorSoh(approvalSku, parentLocation,
                        approvalAvailQtyMap);
            }
        }

        return parentOrderNo;
    }

    private MLDLocation getParentLocation(ApprovalSku approvalSku,
            MLDLocation fulFillingLocation) throws AllocException {
        if (Utility.equals(fulFillingLocation.getLocationId(),
                approvalSku.getWhId())) {
            return fulFillingLocation;
        }

        MLDLocation rootMldLoc = approvalSku.getItemSource().getMldPath()
                .getMldLocation(approvalSku.getWhId());

        if (rootMldLoc != null
                && Utility.equals(rootMldLoc.getLocationId(),
                        fulFillingLocation.getParentLocationId())) {
            return rootMldLoc;
        }

        MLDLocation childMldLoc = rootMldLoc
                .getMldChildLocation(fulFillingLocation.getParentLocationId());

        return childMldLoc;
    }

    private boolean ancestorMatches(String parentLocId, ApprovalSku approvalSku)
            throws AllocException {
        if (Utility.equals(parentLocId, approvalSku.getWhId())) {
            return true;
        }
        MLDLocation rootMldLoc = approvalSku.getItemSource().getMldPath()
                .getMldLocation(approvalSku.getWhId());
        MLDLocation childMldLoc = rootMldLoc.getMldChildLocation(parentLocId);
        if (childMldLoc != null) {
            return true;
        }

        return false;
    }

    private AlcItemSourceLocationKey buildKey(AAlcItemSource itemSource,
            MLDLocation location) {
        String itemId = itemSource.getId();
        String aggDiffId = itemSource.getAggregateDiffId();
        String whId = itemSource.getWarehouseNo();
        long releaseDateTime = itemSource.getReleaseDate().getTime();
        String locationId = location.getLocationId();
        String orderNo = itemSource.getOrderNo();

        AlcItemSourceLocationKey key = AlcItemSourceLocationKey.buildInstance(
                itemId, aggDiffId, whId, releaseDateTime, locationId, orderNo);

        return key;
    }

    private AlcItemSourceLocation getItemLocFromMLDLocation(MLDLocation location) {
        AlcItemSourceLocation itemLoc = null;
        if (location.getAlcItemSourceLocations() != null
                && location.getAlcItemSourceLocations().size() > 0
                && location.getAlcItemSourceLocations().get(0) != null) {
            itemLoc = (AlcItemSourceLocation) location
                    .getAlcItemSourceLocations().get(0);
        }
        return itemLoc;
    }

    private List getLocationIdsForApproval(Allocation alloc)
            throws AllocException {
        ALocationGroupListBuilder builder = LocationGroupListBuilderFactory
                .createBuilder(alloc);

        List locationsList = builder.buildGroupList(alloc.getItemSourceList()
                .getAAlcItemSourceList());

        List locationIdsList = new ArrayList();
        for (int i = 0; i < locationsList.size(); i++) {
            AlcLocation loc = (AlcLocation) locationsList.get(i);
            locationIdsList.add(loc.getLocationId());
        }
        return locationIdsList;
    }

    private RetekDate getInStoreDateForItemLoc(MLDLocation location) {
        AlcItemSourceLocation itemLoc = getItemLocFromMLDLocation(location);

        RetekDate isd = null;
        if (itemLoc != null) {
            isd = itemLoc.getInStoreRetekDate();
        }
        return isd;
    }

    private boolean isRushFlagForItemLoc(MLDLocation location) {
        AlcItemSourceLocation itemLoc = getItemLocFromMLDLocation(location);

        boolean rushFlag = false;
        if (itemLoc != null) {
            rushFlag = itemLoc.isRushFlag();
        }
        return rushFlag;
    }

    public List scrunch(List xrefList) {
        Map mapOfList = new HashMap();
        List headers = null;
        for (int i = 0; i < xrefList.size(); i++) {
            PreAllocHeader header = (PreAllocHeader) xrefList.get(i);
            String key = header.createKey();
            headers = (List) mapOfList.get(key);
            if (headers == null) {
                headers = new ArrayList();
                mapOfList.put(key, headers);
            }
            headers.add(header);
        }

        List xrefAllocHeaders = new ArrayList();
        Iterator iter = mapOfList.values().iterator();
        while (iter.hasNext()) {
            Map mapOfDetails = new HashMap();
            headers = (List) iter.next();
            for (int i = 0; i < headers.size(); i++) {
                PreAllocHeader header = (PreAllocHeader) headers.get(i);
                PreAllocDetail detail = (PreAllocDetail) mapOfDetails
                        .get(header.getPreAllocDetail().getToLoc());
                if (detail == null) {
                    detail = header.getPreAllocDetail();
                    mapOfDetails.put(detail.getToLoc(), detail);
                } else {
                    detail.setQtyAllocated(detail.getQtyAllocated()
                            + header.getPreAllocDetail().getQtyAllocated());
                }
            }
            PreAllocHeader earliestHeader = getEarliestHeader(headers);
            XrefAllocHeader xrefAllocHeader = new XrefAllocHeader(
                    earliestHeader);
            xrefAllocHeader.setDetailsFromMap(mapOfDetails);
            xrefAllocHeaders.add(xrefAllocHeader);
        }

        return xrefAllocHeaders;
    }

    private PreAllocHeader getEarliestHeader(List headers) {
        int size = headers == null ? 0 : headers.size();
        PreAllocHeader earliestHeader = null;
        for (int i = 0; i < size; i++) {
            PreAllocHeader header = (PreAllocHeader) headers.get(i);
            if (earliestHeader == null
                    || (header.getReleaseDate() != null && header
                            .getReleaseDate().before(
                                    earliestHeader.getReleaseDate()))) {
                earliestHeader = header;
            }
        }
        return earliestHeader;
    }

    private Integer getNextXref(Set set) {
        Iterator iter = set.iterator();
        Integer current = new Integer(-1);
        Integer prev = null;

        while (iter.hasNext()) {
            prev = (Integer) iter.next();
            if (prev.intValue() > current.intValue()) {
                current = prev;
            }
        }
        return new Integer(current.intValue() + 1);
    }

    private String buildHeaderKey(String itemId, String whId, String orderNo) {
        return itemId + ":" + whId + ":" + orderNo;
    }

    private Map convertXrefHeadersToMap(List list) {
        Map map = new HashMap();

        for (int i = 0; i < list.size(); i++) {
            XrefAllocHeader header = (XrefAllocHeader) list.get(i);
            String orderNo = null;
            if (header.getDoc() == null || header.getDoc().equals("")) {
                orderNo = null;
            } else {
                orderNo = header.getDoc();
            }
            map.put(buildHeaderKey(header.getItemId(), header.getWhId(),
                    orderNo), header);
        }
        return map;
    }

    public void deleteXrefAlloc(Allocation alloc) throws AllocException {
        Connection conn = null;
        try {
            conn = getConnection();

            if (conn.getAutoCommit() == true)
                conn.setAutoCommit(false);

            AStatusDao asb = DaoFactory.getAStatusDaoInstance();
            asb.setAllocId(alloc.getId());
            asb.setConnection(conn);
            asb.setStatus(alloc.getAllocationStatus());
            if (alloc.getIsApproveSuccess()) {
                asb.deleteXrefAllocNew();
            } else {
                asb.deleteXrefAlloc();
                // asb.updateAlcAllocStatus();
            }
            if (conn.getAutoCommit() == false)
                conn.commit();
        } catch (SQLException e) {
            try {
                if (conn.getAutoCommit() == false)
                    conn.rollback();
            } catch (SQLException e1) {
                // ignore this
            }

            throw new AllocException("51205", e);
        } finally {
            releaseConnection(conn);
        }
    }

    public void updateXrefAllocStatus(long allocId, AllocationStatus status)
            throws AllocException {
        Connection conn = null;
        try {
            conn = getConnection();

            if (conn.getAutoCommit() == true)
                conn.setAutoCommit(false);

            // update alloc_header.status
            AStatusDao asb = DaoFactory.getAStatusDaoInstance();
            asb.setAllocId(allocId);
            asb.setConnection(conn);
            asb.setStatus(status);

            asb.updateXrefAllocStatus();
            asb.updateAlcAllocStatus();

            if (conn.getAutoCommit() == false)
                conn.commit();

        } catch (SQLException e) {
            try {
                if (conn.getAutoCommit() == false)
                    conn.rollback();
            } catch (SQLException e1) {
                // ignore this
            }

            throw new AllocException("51205", e);
        } finally {
            releaseConnection(conn);
        }
    }

    private String getDocType(int type) {
        String docType = null;

        if (type == Source.ASN) {
            docType = "ASN";
        } else if (type == Source.BOL) {
            docType = "BOL";
        } else if (type == Source.PO) {
            docType = "PO";
        } else if (type == Source.TSF) {
            docType = "TSF";
        } else
        // Source.WAREHOUSE
        {
            docType = "";
        }

        return docType;
    }

    private void adjustForSOM(Allocation alloc, List tierOneScrunched)
            throws AllocException {

        Iterator iter = tierOneScrunched.iterator();

        while (iter.hasNext()) {
            XrefAllocHeader header = (XrefAllocHeader) iter.next();
            AlcItemSourceLocation itemLoc = alloc.getItemSourceLocationList()
                    .getItemSourceLocation(header.getItemId());
            double som = itemLoc.getSomRespectingBreakPack();
            List details = header.getXrefAllocDetails();
            for (int i = 0; i < details.size(); i++) {
                XrefAllocDetail detail = (XrefAllocDetail) details.get(i);

                detail.setQtyAllocated(Utility.RoundUpToSOM(
                        detail.getQtyAllocated(), som));
            }
        }
    }

    private int adjustForSom(int qty, MLDLocation parentLoc,
            ApprovalSku approvalSku) throws AllocException {
        double som = 1;
        double approvalQty;
        if (approvalSku.getItemSource().getWarehouseNo()
                .equals(parentLoc.getLocationId())) {
            som = approvalSku.getItemSource().getSom(parentLoc.isBreakPack());
            approvalQty = Utility.RoundUpToSOM(qty, som);
        } else {
            approvalQty = qty;
        }

        return (int) approvalQty;
    }

    public int findNextDestinationFinalAllocatedQty(Allocation alloc)
            throws AllocException {
        int totalNextDestinationFinalAllocatedQty = 0;

        List approvalSkus = null;

        List locationIds = getLocationIdsForApproval(alloc);

        Iterator iter = alloc.getItemSourceList().getAAlcItemSourceList()
                .buildMLDPaths().iterator();
        while (iter.hasNext()) {
            MLDPath mldPath = (MLDPath) iter.next();

            approvalSkus = buildItemSourceApprovalSkus(alloc, mldPath);

            for (int i = 0; i < approvalSkus.size(); i++) {
                ApprovalSku approvalSku = (ApprovalSku) approvalSkus.get(i);

                MLDPath filteredPath = mldPath.getFilteredPath(
                        approvalSku.getWhId(), locationIds);

                MLDLocation tierOneLocation = filteredPath
                        .getMldLocation(approvalSku.getWhId());

                if (tierOneLocation == null) {
                    continue;
                }

                Iterator nextDestinationChildrenIter = tierOneLocation
                        .getMldLocations().values().iterator();
                while (nextDestinationChildrenIter.hasNext()) {
                    MLDLocation childLoc = (MLDLocation) nextDestinationChildrenIter
                            .next();
                    Iterator itemLocIter = childLoc.getAlcItemSourceLocations()
                            .iterator();
                    while (itemLocIter.hasNext()) {
                        AlcItemSourceLocation itemLoc = (AlcItemSourceLocation) itemLocIter
                                .next();
                        totalNextDestinationFinalAllocatedQty += itemLoc
                                .getFinalAllocatedQty().intValue();
                    }
                }
            }
        }

        return totalNextDestinationFinalAllocatedQty;
    }

    public Collection buildPathsFromDefaultWarehouse(Allocation alloc)
            throws AllocException {
        Collection newMldPaths = new HashSet();

        Map mapOfMldParents = buildMldLocations(alloc);

        Iterator itemSourcesIter = alloc.getItemSourceList()
                .getAAlcItemSourceList().getAlcItemSources().iterator();
        while (itemSourcesIter.hasNext()) {
            AAlcItemSource itemSource = (AAlcItemSource) itemSourcesIter.next();
            // MLDPath mldPath = itemSource.getMldPath();
            MLDPath mldPath = new MLDPath();
            itemSource.setMldPath(mldPath);
            MLDLocation parentLoc = (MLDLocation) mapOfMldParents
                    .get(itemSource.getWarehouseNo());
            if (parentLoc != null) {
                mldPath.add(parentLoc);
            }
            newMldPaths.add(mldPath);
        }

        return newMldPaths;
    }

    private Map buildMldLocations(Allocation alloc) throws AllocException {
        Map newMap = new HashMap();

        AAlcItemSourceList itemSourcesList = alloc.getItemSourceList()
                .getAAlcItemSourceList();

        ALocationGroupListBuilder builder = LocationGroupListBuilderFactory
                .createBuilder(alloc);
        List validLocations = builder.buildGroupList(itemSourcesList);

        Iterator iter = validLocations.iterator();

        Map map = alloc.getItemSourceLocationList()
                .getItemSourceLocationMapByItemLocation();

        while (iter.hasNext()) {
            AlcLocation loc = (AlcLocation) iter.next();

            Iterator iterator = itemSourcesList.iterator();
            AAlcItemSource itemSource;

            while (iterator.hasNext()) {
                itemSource = (AAlcItemSource) iterator.next();

                MLDLocation childMldLoc = new MLDLocation();
                childMldLoc.setLocationId(loc.getLocationId());

                List itemSourceLocs = (List) map.get(loc.getLocationId() + "~"
                        + itemSource.getWarehouseNo());

                if (itemSourceLocs != null) {
                    childMldLoc.setAlcItemSourceLocations((List) map.get(loc
                            .getLocationId()
                            + "~"
                            + itemSource.getWarehouseNo()));

                    MLDLocation parentMldLoc = (MLDLocation) newMap
                            .get(itemSource.getWarehouseNo());

                    if (parentMldLoc == null) {
                        parentMldLoc = new MLDLocation();
                        parentMldLoc.setLocationId(itemSource.getWarehouseNo());
                        parentMldLoc.setBreakPack(getWHBreakPackInd(itemSource
                                .getWarehouseNo()));
                        newMap.put(parentMldLoc.getLocationId(), parentMldLoc);
                    }

                    childMldLoc.setStore(true);
                    parentMldLoc.add(childMldLoc);
                }
            }
        }

        return newMap;
    }

    private List removeNonNextDestinationXrefAllocHeaders(Allocation alloc,
            List xrefAllocHeaders) throws AllocException {
        List nonNextDestinationXrefHeaders = new ArrayList();
        Set nextDestinationWarehouses = getNextDesintationWarehouses(alloc);

        for (int i = 0; i < xrefAllocHeaders.size(); i++) {
            XrefAllocHeader xrefAllocHeader = (XrefAllocHeader) xrefAllocHeaders
                    .get(i);

            List validXrefAllocDetail = new ArrayList();

            Iterator xrefAllocDetailIter = xrefAllocHeader
                    .getXrefAllocDetails().iterator();
            while (xrefAllocDetailIter.hasNext()) {
                XrefAllocDetail xrefAllocDetail = (XrefAllocDetail) xrefAllocDetailIter
                        .next();

                if (nextDestinationWarehouses.contains(xrefAllocDetail
                        .getToLoc())) {
                    validXrefAllocDetail.add(xrefAllocDetail);
                }
            }

            if (validXrefAllocDetail.size() > 0) {
                xrefAllocHeader.setXrefAllocDetails(validXrefAllocDetail);
                nonNextDestinationXrefHeaders.add(xrefAllocHeader);
            }
        }

        return nonNextDestinationXrefHeaders;
    }

    private Set getNextDesintationWarehouses(Allocation alloc)
            throws AllocException {
        Set nextDestinationWarehouses = new HashSet();

        Iterator itemSourcesIter = alloc.getItemSourceList()
                .getAAlcItemSourceList().iterator();

        while (itemSourcesIter.hasNext()) {
            AAlcItemSource itemSource = (AAlcItemSource) itemSourcesIter.next();
            MLDPath mldPath = itemSource.getMldPath().getFilteredPath(
                    itemSource.getWarehouseNo(),
                    alloc.getLocationGroupList().getLocationIds());

            Iterator mldLocations = mldPath.getMldLocations().iterator();

            while (mldLocations.hasNext()) {
                MLDLocation mldLocation = (MLDLocation) mldLocations.next();

                Iterator nextDestinationIter = mldLocation.getMldLocations()
                        .values().iterator();

                while (nextDestinationIter.hasNext()) {
                    MLDLocation nextDestinationMldLocation = (MLDLocation) nextDestinationIter
                            .next();
                    nextDestinationWarehouses.add(nextDestinationMldLocation
                            .getLocationId());
                }
            }
        }

        return nextDestinationWarehouses;
    }

    private void deleteItemSourceShipSchedule(Allocation alloc)
            throws AllocException {
        if (alloc.isMldAllocation()
                && AllocationProperties.getHandle().getDistributionLevel() == PathBuilder.DISTRIBUTION_LEVEL_MLD_SHIP_SCHEDULE) {
            List clonedItemSources = alloc.getItemSourceList()
                    .getAAlcItemSourceList().getClonedListWithMldPath();

            ServiceFactory.getShippingScheduleService()
                    .deleteItemSourcesShipScheduleIfMLDAndShippingSchedule(
                            alloc);

            try {
                AlcItemSourceLocationList itemSourceLocationList = new AlcItemSourceLocationList();
                itemSourceLocationList.setAllocation(alloc);
                itemSourceLocationList.load(alloc.getEnforceWhStoreRelInd(),
                        alloc.isRecalc());
                alloc.setItemSourceLocationList(itemSourceLocationList);

                ServiceFactory.getShippingScheduleService()
                        .insertItemSourceShippingSchedule(
                                alloc.getItemSourceList()
                                        .getAAlcItemSourceList()
                                        .getAlcItemSources(),
                                alloc.getLocationGroupList().getLocationIds());
            } catch (AllocException ae) {
                ServiceFactory.getShippingScheduleService()
                        .insertItemSourceShippingSchedule(clonedItemSources,
                                alloc.getLocationGroupList().getLocationIds());

                throw new AllocException(
                        "AllocSummary.ship_schedule_has_changed", ae);
            }
        }
    }

    private boolean getWHBreakPackInd(String whno) throws AllocException {
        Connection conn = null;
        boolean brkPackInd = false;
        try {
            conn = getConnection();
            WhDao whDao = new WhDao();
            whDao.setConnection(conn);
            brkPackInd = whDao.getWhBreakPackInd(whno);

        } finally {
            releaseConnection(conn);
        }
        return brkPackInd;

    }

    protected List<PreAllocHeader> buildXrefListForPackDistribution(
            Allocation allocation) throws AllocException {
        AlcItemSourceLocationList itemSourceLocationList = allocation
                .getItemSourceLocationList();

        ArrayList<PreAllocHeader> preAllocHeaderList = new ArrayList<PreAllocHeader>();

        for (int i = 0; i < itemSourceLocationList.size(); i++) {
            AlcItemSourceLocation alcItemSourceLocation = itemSourceLocationList
                    .get(i);

            PreAllocHeader preAllocHeader = createPreAllocHeaderPackDistribution(
                    allocation, alcItemSourceLocation, i);

            preAllocHeaderList.add(preAllocHeader);
        }

        return preAllocHeaderList;
    }
}
