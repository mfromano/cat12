function Ycls = cat_main(res,tpm,job)
% ______________________________________________________________________
% Write out CAT preprocessed data
%
% FORMAT Ycls = cat_main(res,tpm,job)
%
% based on John Ashburners version of
% spm_preproc_write8.m 2531 2008-12-05 18:59:26Z john $
%
% ______________________________________________________________________
%
% Christian Gaser, Robert Dahnke
% Structural Brain Mapping Group (https://neuro-jena.github.io)
% Departments of Neurology and Psychiatry
% Jena University Hospital
% ______________________________________________________________________
% $Id$

%#ok<*ASGLU>


update_intnorm = 1; %job.extopts.new_release;  % RD202101: temporary parameter to control the additional intensity normalization 

if ~isfield(job.extopts,'histth'), job.extopts.histth = [0.96 0.9999]; end  % RD20200501: created in cat_run_job but not in cat_run_job1639

% if there is a breakpoint in this file set debug=1 and do not clear temporary variables 
dbs = dbstatus; debug = 0; for dbsi=1:numel(dbs), if strcmp(dbs(dbsi).name,mfilename); debug = 1; break; end; end

% error report structure
global cat_err_res
  

%% Update SPM/CAT parameter and add some basic variables
[res,job,VT,VT0,pth,nam,vx_vol,d] = cat_main_updatepara(res,tpm,job);



%% Write SPM preprocessing results
%  -------------------------------------------------------------------
stime  = cat_io_cmd('SPM preprocessing 2 (write)'); if job.extopts.verb>1, fprintf('\n'); end
stime2 = cat_io_cmd('  Write Segmentation','g5','',job.extopts.verb-1);
[Ysrc,Ycls,Yy] = cat_spm_preproc_write8(res,zeros(max(res.lkp),4),zeros(1,2),[0 0],0,0);



%% CAT vs. SPMpp Pipeline
if ~isfield(res,'spmpp')
  %% Update SPM results in case of reduced SPM preprocessing resolution 
  %  -------------------------------------------------------------------
  if isfield(res,'redspmres')
    [Ysrc,Ycls,Yy,res] = cat_main_resspmres(Ysrc,Ycls,Yy,res);
  end
  
  
  
  %% Replace SPM brain segmentation by AMAP segmentation
  %  -------------------------------------------------------------------
  %  This is an alternative pipeline in case of failed SPM brain tissue
  %  classification in datasets with abnormal anatomy, i.e. superlarge 
  %  ventricle. However, SPM is used for head tissue classification and
  %  bias correction. 
  %  -------------------------------------------------------------------
  if isfield(job.extopts,'spm_kamap') && job.extopts.spm_kamap 
    [P,res,stime2] = cat_main_kamap(Ysrc,Ycls,Yy,tpm,job,res,vx_vol,stime2);
  else
    P = zeros([size(Ycls{1}) numel(Ycls)],'uint8');
    for i=1:numel(Ycls), P(:,:,:,i) = Ycls{i}; end
  end
  clear Ycls;
  
  

  %% Update SPM preprocessing 
  %  -------------------------------------------------------------------
  %  Fix class errors, brainmask etc. 
  %  This is a large and important subfuction that represent the 
  %  starting point of the refined CAT preprocessing.
  %  RD202006: add ignoreErrors backup
  %  RD202101: small difference to 1639
  %  -------------------------------------------------------------------
  [Ysrc,Ycls,Yb,Yb0,Yy,job,res,trans,T3th,stime2] = cat_main_updateSPM(Ysrc,P,Yy,tpm,job,res,stime,stime2);
  %[Ysrc,Ycls,Yb,Yb0,job,res,T3th,stime2] = cat_main_updateSPM1639(Ysrc,P,Yy,tpm,job,res,stime,stime2);
  clear P; 
  
  
  
  %% Check the previous preprocessing in debug mode ###
  %  -------------------------------------------------------------------
  %  If you want to see intermediate steps of the processing use the "ds"
  %  function:
  %    ds('l2','',vx_vol,Ym,Yb,Ym,Yp0,80)
  %  that display 4 images (unterlay, overlay, image1, image2) for one 
  %  slice. The images were scaled in a range of 0 to 1. The overlay 
  %  allows up to 20 colors
  %  -------------------------------------------------------------------
  if debug;;
    Ym   = Ysrc / max(T3th(1:3)); %#ok<NASGU> % only WM scaling
    Yp0  = (single(Ycls{1})/255*2 + single(Ycls{2})/255*3 + single(Ycls{3})/255)/3; %#ok<NASGU> % label map
  end
  
  

  %% Global (and local) intensity normalization and partioning 
  %  ---------------------------------------------------------------------
  %  Global and local intensity corrections are the basis of most of the 
  %  following functions. The global normalization based on the SPM tissue
  %  thresholds (res.mn) and were used anyway. For strong differences 
  %  (mostly by the CSF) the median will used, because it is e.g. more 
  %  stable. This will cause a warning by the cat_main_gintnorm.
  %
  %  The local adaptive segmentation include a further bias correction  
  %  and a global  and local intensity correction. The local intensity 
  %  correction refines the tissue maps to aproximate the local tissue 
  %  peaks of WM (maximum-based), GM, and CSF. 
  %
  %  RD202006: add ignoreErrors backup
  %  ---------------------------------------------------------------------
  stime = cat_io_cmd('Global intensity correction');
  if all(vx_vol < 0.4 ) && strcmp(job.extopts.species,'human')%&& job.extopts.ignoreErros<2 % 1639
    % guaranty average (lower) resolution with >0.7 mm
    % RD202006: This solution is not working when cat_main_gintnorm
    %           optimize the image (e.g. bias correction). Just calling
    %               Ym  = cat_main_gintnorm(Ysrc,Tth);  
    %           would not include the bias correction but also may use 
    %           inacurate peaks that were estimated on slighly different 
    %           image. So it is more save to turn it off because running 
    %           the default case also in highres data only increase time
    %           and memory demands. 
    %           Possible test subject: ADHD200/ADHD200_HC_BEJ_1050345_T1_SD000000-RS00.nii        
    [Ysrcr,resGI] = cat_vol_resize(Ysrc      , 'reduceV', vx_vol, 0.6, 32, 'meanm');
    Ybr           = cat_vol_resize(single(Yb), 'reduceV', vx_vol, 0.6, 32, 'meanm')>0.5;
    Yclsr = cell(size(Ycls)); for i=1:6, Yclsr{i} = cat_vol_resize(Ycls{i},'reduceV',vx_vol,0.6,32); end
    [Ymr,T3th,Tth,job.inv_weighting,noise] = cat_main_gintnorm(Ysrcr,Yclsr,Ybr,resGI.vx_volr,res,job.extopts);
    clear Ymr Ybr Ysrcr Yclsr; 
    Ym = cat_main_gintnorm(Ysrc,Tth); 
  else
%    [Ym,Yb,T3th,Tth,job.inv_weighting,noise] = cat_main_gintnorm1639(Ysrc,Ycls,Yb,vx_vol,res,Yy,job.extopts); % Yb2    
    [Ym,T3th,Tth,job.inv_weighting,noise] = cat_main_gintnorm(Ysrc,Ycls,Yb,vx_vol,res,job.extopts);
  end
  job.extopts.inv_weighting = job.inv_weighting;
  res.ppe.tths.gintnorm.T3th = T3th; 
  res.ppe.tths.gintnorm.Tth  = Tth; 

  % RD202101: additional intensity correction 
  if 0 && update_intnorm 
    [Ym,tmp,Tthm] = cat_main_update_intnorm(Ym,Ym,Yb,Ycls,job); 
    res.ppe.tths.uintnorm0postgintnorm.Tthm  = Tthm; 
    clear tmp Tthm;
  end

  

  %% Enhanced denoising with intensity (contrast) normalized data
  %  ---------------------------------------------------------------------
  %  After the intensity scaling and with correct information about the
  %  variance of the tissue, a further harder noise correction is meaningful.
  %  Finally, a stronger NLM-filter is better than a strong MRF filter!
  %  ---------------------------------------------------------------------
  if job.extopts.NCstr~=0  
    NCstr.labels = {'none','full','light','medium','strong','heavy'};
    NCstr.values = {0 1 2 -inf 4 5}; 
    stime = cat_io_cmd(sprintf('SANLM denoising after intensity normalization (%s)',...
      NCstr.labels{find(cell2mat(NCstr.values)==job.extopts.NCstr,1,'first')}));
    
    % filter only within the brain mask for speed up
    [Yms,Ybr,BB] = cat_vol_resize({Ym,Yb},'reduceBrain',vx_vol,round(2/cat_stat_nanmean(vx_vol)),Yb); Ybr = Ybr>0.5; 
    Yms = cat_vol_sanlm(struct('data',res.image0.fname,'verb',0,'NCstr',job.extopts.NCstr),res.image,1,Yms); 
    Ym(BB.BB(1):BB.BB(2),BB.BB(3):BB.BB(4),BB.BB(5):BB.BB(6)) = Yms .* Ybr + ...
      Ym(BB.BB(1):BB.BB(2),BB.BB(3):BB.BB(4),BB.BB(5):BB.BB(6)) .* (1-Ybr);
    clear Yms Ybr BB;
    
    Ysrc = cat_main_gintnormi(Ym,Tth);
    
    fprintf('%5.0fs\n',etime(clock,stime));
  end
  
  
  

  %% prepared for improved partitioning - RD20170320, RD20180416
  %{
  %  Update the initial SPM normalization by a fast version of Shooting 
  %  to improve the skull-stripping, the partitioning and LAS.
  %  We need stong deformations in the ventricle for the partitioning 
  %  but low deformations for the skull-stripping. Moreover, it has to 
  %  be really fast > low resolution (3 mm) and less iterations. 
  %  The mapping has to be done for the TPM resolution, but we have to 
  %  use the Shooting template for mapping rather then the TPM because
  %  of the cat12 atlas map.
  %  
  %  #### moved fast shooting to the cat_main_updateSPM function ####
  % 
  if 0 % job.extopts.WMHC || job.extopts.SLC
    stime = cat_io_cmd(sprintf('Fast registration'),'','',job.extopts.verb); 

    res2 = res; 
    job2 = job;
    job2.extopts.verb       = debug;  % do not display process (people would may get confused) 
    job2.extopts.vox        = abs(res.tpm(1).mat(1));  % TPM resolution to replace old Yy  
    if job.extopts.regstr>0
      job2.extopts.regstr     = 15;     % low resolution 
      job2.extopts.reg.nits   = 16;     % less iterations
      job2.extopts.reg.affreg = 0;      % new affine registration
      job2.extopts.shootingtpms(3:end) = [];             % remove high templates, we only need low frequency corrections
      res2 = res; 
      res2.do_dartel          = 2;      % use shooting
    else
      fprintf('\n');
      job2.extopts.verb        = 0; 
      job2.extopts.vox         = abs(res.tpm(1).mat(1));  % TPM resolution to replace old Yy 
      job2.extopts.reg.iterlim = 1;      % only 1-2 inner iterations
      job2.extopts.reg.affreg  = 0;      % new affine registration
      res2.do_dartel           = 1;      % use dartel
    end
    if isfield(res,'Ylesion') && sum(res.Ylesion(:)>0)
      [trans,res.ppe.reginitp] = cat_main_registration(job2,res2,Ycls(1:2),Yy,res.Ylesion); 
    else
      [trans,res.ppe.reginitp] = cat_main_registration(job2,res2,Ycls(1:2),Yy); 
    end
    Yy2  = trans.warped.y;
    if ~debug, clear trans job2 res2; end

    % Shooting did not include areas outside of the boundary box
    %
    % ### add to cat_main_registration?
    %
    Ybd = true(size(Ym)); Ybd(3:end-2,3:end-2,3:end-2) = 0; Ybd(~isnan(Yy2(:,:,:,1))) = 0; Yy2(isnan(Yy2))=0; 
    for k1=1:3
      Yy2(:,:,:,k1) = Yy(:,:,:,k1) .* Ybd + Yy2(:,:,:,k1) .* (1-Ybd);
      Yy2(:,:,:,k1) = cat_vol_approx(Yy2(:,:,:,k1),'nn',vx_vol,3); 
    end
    Yy = Yy2; 
    clear Yy2; 
    if ~debug, fprintf('%5.0fs\n',etime(clock,stime)); end
  end
  %}
  


  %% Local Intensity Correction 
  %  RD202006: Skip LAS in case of inverse contrast or if backup functions
  %            are forced (ignoreErrors > 2). 
  %  RD202101: There are multiple differnces by intensity scaling that are
  %            handeled by the AMAP but still affect the surface pipeline 
  %            > added final intensity correction based on the AMAP
  %  RD202102: Extension of LAS to correct protocoll depending differences
  %            of cortical GM intensities due to myelination before and 
  %            after the general call of the LAS function.
  %            > add this later to the LAS function inclusive the denoising
  %            > this may also work for T2/PD maps 
  if job.extopts.LASstr>0 && job.extopts.ignoreErrors < 3 && ~job.extopts.inv_weighting
    if job.extopts.LASstr>1 || job.extopts.inv_weighting
      extoptsLAS2 = job.extopts;
      extoptsLAS2.LASstr = mod(extoptsLAS2.LASstr,1); 
      stime = cat_io_cmd(sprintf('Simplified Local adaptive segmentation (LASstr=%0.2f)',extoptsLAS2.LASstr));
    else
      stime = cat_io_cmd(sprintf('Local adaptive segmentation (LASstr=%0.2f)',job.extopts.LASstr)); 
    end

    % RD202102: Extension of LAS to correct protocoll depending differences
    %           of cortical GM intensities due to myelination.   
    if isfield(job.extopts,'LASmyostr') 
      LASmyostr = job.extopts.LASmyostr; 
    else
      LASmyostr = job.extopts.LASstr; 
    end
    % LASmyostr = min(1,LASmyostr + 0.5*job.extopts.inv_weighting); % force correction in case of inverse data?
    if LASmyostr 
      stime2  = cat_io_cmd(sprintf('\n  LAS myelination correction (LASmyostr=%0.2f)',LASmyostr),'g5','',job.extopts.verb); 
      vx_volo = sqrt(sum(res.image0(1).mat(1:3,1:3).^2));
      % It is better to avoid updating of the Ym and Ysrc here because some
      % of the problems depend on inhomogenities that can be corrected by 
      % LAS and a final correct at the end.
      [Ymx,Ysrcx,Ycls,Ycor,glcor,tmp] = cat_main_correctmyelination(Ym,Ysrc,Ycls,Yb,vx_vol,vx_volo,T3th,LASmyostr,Yy,job.extopts.cat12atlas,res.tpm);
      fprintf('%6.0fs\n',etime(clock,stime2)); clear Ymx Ysrcx;
    end

    % LAS main call 
    if job.extopts.LASstr>1 || job.extopts.inv_weighting
      [Ymi,Ymt,Ycls] = cat_main_LASs(Ysrc,Ycls,Ym,Yb,Yy,Tth,res,vx_vol,extoptsLAS2); % use Yclsi after cat_vol_partvol
    else
      [Ymi,Ymt,Ycls] = cat_main_LAS2(Ysrc,Ycls,Ym,Yb,Yy,T3th,res,vx_vol,job.extopts,Tth);
    end
    clear Ymt; % use original global scaled ... 
    stime2 = clock; % not really correct but better than before

    % RD202102:   update Ymi since the LAS correction is currently not local enough in case of artefacts 
    if LASmyostr 
      Ymi = max( min( Ymi , min( 2.5 , Ymi )*0.25 + 0.75*( 2.5 - 0.5 * LASmyostr) / 3 ) , Ymi - Ycor / 3 );
      clear Yp0; 
    end
  else
    % just a node because it is the result of the inverse contrast warning
    cat_io_addwarning('cat_main:skipLAS','Skip LAS due to image contrast. Use global normalization.',0,[0 1]);
    Ymi = Ym; 
  end

  % ### indlcude this in cat_main_LAS? ###
  if job.extopts.NCstr~=0 
    % noise correction of the local normalized image Ymi, whereas only small changes are expected in Ym by the WM bias correction
    stimen = cat_io_cmd(sprintf('  SANLM denoising after LAS (%s)',...
      NCstr.labels{find(cell2mat(NCstr.values)==job.extopts.NCstr,1,'first')}),'g5','',1,stime2);

    [Ymis,Ymior,BB]  = cat_vol_resize({Ymi,Ym},'reduceBrain',vx_vol,round(2/mean(vx_vol)),Yb);
    Ymis = cat_vol_sanlm(struct('data',res.image0.fname,'verb',0,'NCstr',job.extopts.NCstr),res.image,1,Ymis);

    Yc = abs(Ymis - Ymior); Yc = Yc * 6 * min(2,max(0,abs(job.extopts.NCstr))); 
    spm_smooth(Yc,Yc,2./vx_vol); Yc = max(0,min(1,Yc)); clear Ymior; 
    % mix original and noise corrected image and go back to original resolution
    Ybr = Yb(BB.BB(1):BB.BB(2),BB.BB(3):BB.BB(4),BB.BB(5):BB.BB(6));
    Ymi(BB.BB(1):BB.BB(2),BB.BB(3):BB.BB(4),BB.BB(5):BB.BB(6)) = ...
      Ymi(BB.BB(1):BB.BB(2),BB.BB(3):BB.BB(4),BB.BB(5):BB.BB(6)) .* (1-Ybr) + ...
      (1-Yc) .* Ymi(BB.BB(1):BB.BB(2),BB.BB(3):BB.BB(4),BB.BB(5):BB.BB(6)) .* Ybr + ...
      Yc .* Ymis .* Ybr;

    % extreme background denoising to remove wholes?
    Ymis = cat_vol_median3(Ymi,Ymi>0 & Ymi<0.4,Ymi<0.4); Ymi = Ymi.*max(0.1,Ymi>0.4) + Ymis.*min(0.9,Ymi<=0.4);
    Ymis = cat_vol_median3(Ym,Ym>0 & Ym<0.4,Ym<0.4); Ym = Ym.*max(0.1,Ym>0.4) + Ymis.*min(0.9,Ym<=0.4);

    %cat_io_cmd(' ','','',job.extopts.verb,stimen); 
    clear Ymis;
  else
    stimen = stime; 
  end    

  cat_io_cmd(' ','','',job.extopts.verb,stimen); clear stimenc
  fprintf('%5.0fs\n',etime(clock,stime)); 
  
  if ~debug; clear Ysrc ; end
  
  
  % RD202101: additional intensity correction 
  if update_intnorm 
    try
      [Ym,Ymi,Tthm,Tthmi] = cat_main_update_intnorm(Ym,Ymi,Yb,Ycls,job);
      res.ppe.tths.uintnorm1postlas.Tthm  = Tthm; 
      res.ppe.tths.uintnorm1postlas.Tthmi = Tthmi;
      clear Tthm Tthmi; 
    catch
      cat_io_cprintf('warn','Update of intensities failed!\n');
      res.ppe.tths.uintnorm1postlas.Tthm  = nan; 
      res.ppe.tths.uintnorm1postlas.Tthmi = nan;
    end
  end
  
  
  
  %% Partitioning: 
  %  --------------------------------------------------------------------- 
  %  For most of the following adaptations further knowledge of special 
  %  regions is helpfull. Also Ymi is maybe still a little bit inhomogen 
  %  the alignment should work. Only strong inhomogenities can cause 
  %  problems, especially for the blood vessel detection. 
  %  But for bias correction the ROIs are important too, to avoid over
  %  corrections in special regions like the cerbellum and subcortex. 
  %  ---------------------------------------------------------------------
  
  % RD202006: Only correct for WMHs if there is a good contrast
  %           Add this in the partvol function ?
  stime = cat_io_cmd('ROI segmentation (partitioning)');
  if job.extopts.SLC
    if isfield(res,'Ylesion') && sum(res.Ylesion(:)>0)
      [Yl1,Ycls,YMF] = cat_vol_partvol(Ymi,Ycls,Yb,Yy,vx_vol,job.extopts,tpm.V,noise,job,res.Ylesion); %,Ydt,Ydti);
      fprintf('%5.0fs\n',etime(clock,stime));
    else 
      [Yl1,Ycls,YMF] = cat_vol_partvol(Ymi,Ycls,Yb,Yy,vx_vol,job.extopts,tpm.V,noise,job,false(size(Ym)));
      fprintf('%5.0fs\n',etime(clock,stime));
      if isfield(res,'Ylesion') && sum(res.Ylesion(:)==0) && job.extopts.SLC==1
        cat_io_addwarning('cat_main_SLC_noExpDef','SLC is set for manual lesions correction but no lesions were found!',1,[1 1]); 
      end
    end
  else
    [Yl1,Ycls,YMF] = cat_vol_partvol(Ymi,Ycls,Yb,Yy,vx_vol,job.extopts,tpm.V,noise,job,false(size(Ym)));
    fprintf('%5.0fs\n',etime(clock,stime));
    if job.extopts.expertgui && isfield(res,'Ylesion') && sum(res.Ylesion(:))>1000 && job.extopts.ignoreErrors < 2
      cat_io_addwarning('cat_main_SLC_noExpDef',sprintf(['SLC is deactivated but there are %0.2f cm' ...
          native2unicode(179, 'latin1') ' of voxels with zero value inside the brain!'],prod(vx_vol) .* sum(res.Ylesion(:)) / 1000 ),1,[1 1]); 
    end
  end
  if ~debug; clear YBG Ycr Ydt; end


  
  %%  Blood Vessel Correction 
  %  ---------------------------------------------------------------------
  %  Blood vessel correction has to be done before the segmentation to 
  %  remove high frequency strutures and avoid missclassifications.
  %  Problems can occure for strong biased images, because the partioning 
  %  has to be done before bias correction.
  %  Of course we only want to do this for highres T1 data!
  %  ---------------------------------------------------------------------
  NS = @(Ys,s) Ys==s | Ys==s+1; 
  if job.extopts.BVCstr && ~job.extopts.inv_weighting
    if all(vx_vol<2) % ~job.extopts.inv_weighting &&
      stime = cat_io_cmd(sprintf('Blood vessel correction (BVCstr=%0.2f)',job.extopts.BVCstr));
      try 

        Ybv  = cat_vol_smooth3X(cat_vol_smooth3X( ...
          NS(Yl1,7) .* (Ymi*3 - (1.5-job.extopts.BVCstr)),0.3).^4,0.1)/3;

        % correct src images
        Ymi   = max(0,Ymi - Ybv*2/3); 
        Ymi   = cat_vol_median3(Ymi,cat_vol_morph(Ybv>0.5,'dilate')); 
        Ymis  = cat_vol_smooth3X(Ymi); Ymi(Ybv>0.5) = Ymis(Ybv>0.5); clear Ymis;

        % update classes
        Ycls{1} = min(Ycls{1},cat_vol_ctype(255 - Ybv*127)); 
        Ycls{2} = min(Ycls{2},cat_vol_ctype(255 - Ybv*127)); 
        Ycls{3} = max(Ycls{3},cat_vol_ctype(127 * Ybv)); 

        fprintf('%5.0fs\n',etime(clock,stime));
        clear Ybv p0; 
      catch
        cat_io_addwarning('cat_main:noBVCbackup','Error in BVC. No BVC backup function.',1,[0 1]); 
      end
    else
      cat_io_addwarning('cat_main:noBVC4lowres',sprintf('No BVC for low resolution data (%0.2fx%0.2fx%0.2fmm).',vx_vol),1,[0 1]); 
    end
  end

  

  %% gcut+: additional skull-stripping using graph-cut
  %  -------------------------------------------------------------------
  %  For skull-stripping gcut is used in general, but a simple and very 
  %  old function is still available as backup solution.
  %  Furthermore, both parts prepare the initial segmentation map for the 
  %  AMAP function.
  %  RD202006: cat_main_gcut requires T1 weighed input
  %  RD202101: this does not realy fit to your strategy of setting up the
  %            skull-stripping in cat_main_updateSPM and then only refine
  %            it by cleanup. >> remove this option in future
  %  -------------------------------------------------------------------
  if job.extopts.gcutstr>0 && job.extopts.gcutstr<=1 &&  max(res.lkp) ~= 4 
    stime = cat_io_cmd(sprintf('Skull-stripping using graph-cut (gcutstr=%0.2f)',job.extopts.gcutstr));
    if job.extopts.ignoreErrors < 3 
      try 
        [Yb,Yl1] = cat_main_gcut(Ym,Yb,Ycls,Yl1,YMF,vx_vol,job.extopts);

        % extend gcut brainmask by brainmask derived from SPM12 segmentations if necessary
        if ~job.extopts.inv_weighting, Yb = Yb | Yb0; end

        fprintf('%5.0fs\n',etime(clock,stime));
      catch %#ok<CTCH>
        fprintf('\n'); 
        cat_io_addwarning('cat_main_gcut:err99','Unknown error in cat_main_gcut. Use old brainmask.',1,[1 1]);
        job.extopts.gcutstr = 99;
      end
    else
      cat_io_addwarning('cat_main_gcut:err99','No graph-cut backup function. Use old brainmask.',1,[1 1]);
    end
  end
  % correct mask for skull-stripped images (but not ex-vivo brains, where CSF=BG)  
  if max(res.lkp) == 4 %skullstripped
    Yb = Yb .* (spm_read_vols(res.image(1)) > 0);
  end

  
  
  %% AMAP segmentation
  %  -------------------------------------------------------------------
  %  Most corrections were done before and the AMAP routine is used with 
  %  a low level of iterations and no further bias correction, because
  %  some images get tile artifacts. 
  %
  %    prob .. new AMAP segmenation (4D)
  %    ind* .. index elements to asign a subvolume
  %
  %  RD202006: Updated ignoreErrors pipeline that try to use AMAP if 
  %            ignoreError < 4.
  %  RD202101: There are differences by using only the new brainmask
  %  -------------------------------------------------------------------
  job.extopts.AMAPframing   = 1;
  try
    % there is a bug with empty images CG7T >> catch with old function
    [prob,indx,indy,indz,ath] = cat_main_amap(Ymi,Yb,Yb0,Ycls,job,res);
  catch
    [prob,indx,indy,indz,ath] = cat_main_amap1639(Ymi,Yb,Yb0,Ycls,job,res);
  end
  if sum(sum(sum(prob(:,:,:,1)))) < sum(Ycls{1}(:)) * 0.5
    % there is a bug with empty images CG7T >> catch with old function
    [prob,indx,indy,indz,ath] = cat_main_amap1639(Ymi,Yb,Yb0,Ycls,job,res);
  end
  
  % RD202101: Update image intensity normalization based on the the AMAP
  %           segmentation but not the AMAP thresholds
  if update_intnorm 
    [Ym,Ymi,Tthm,Tthmi] = cat_main_update_intnorm(Ym,Ymi,Yb,prob,job,0,indx,indy,indz);
    res.ppe.tths.uintnorm2postamap.Tthm  = Tthm; 
    res.ppe.tths.uintnorm2postamap.Tthmi = Tthmi; 
    clear Tthm Tthmi; 
  end
  
  
  %% Final Cleanup
  %  -------------------------------------------------------------------
  %  There is one major parameter to control the strength of the cleanup.
  %  As far as the cleanup has a strong relation to the skull-stripping, 
  %  cleanupstr is controlled by the gcutstr. 
  %
  %     Yp0ox = single(prob(:,:,:,1))/255*2 + single(prob(:,:,:,2))/255*3 + single(prob(:,:,:,3))/255; 
  %     Yp0o  = zeros(d,'single'); Yp0o(indx,indy,indz) = Yp0ox; 
  %     Yp0   = zeros(d,'uint8'); Yp0(indx,indy,indz) = Yp0b; 
  %  -------------------------------------------------------------------
  if job.extopts.cleanupstr>0
    % classical cleanup with extended version close to the skull in case of
    % the AMAP segmentation (not so good for BUSS_2002)
    res.xCleanup = (isfield(job.extopts,'spm_kamap') && job.extopts.spm_kamap ) | (job.extopts.cleanupstr > 2);
    res.xCleanup = max(res.xCleanup, 3 * ( isfield(job.extopts,'inv_weighting') && job.extopts.inv_weighting )); 
    prob = cat_main_clean_gwc(prob,min(1,job.extopts.cleanupstr*2/mean(vx_vol)),res.xCleanup);
    
    % newer additional cleanup (cleanupstr == 4 to use only the cat_main_clean_gwc for tests)
    if job.extopts.cleanupstr < 3 && ~job.extopts.inv_weighting
      [Ycls,Yp0b] = cat_main_cleanup(Ycls,prob,Yl1(indx,indy,indz),... 
        Ym(indx,indy,indz),job.extopts,job.extopts.inv_weighting,vx_vol,indx,indy,indz); % new cleanup
    else
      for i=1:3, Ycls{i}(:) = 0; Ycls{i}(indx,indy,indz) = prob(:,:,:,i); end
      Yp0b = Yb(indx,indy,indz); 
    end
  else
    for i=1:3, Ycls{i}(:) = 0; Ycls{i}(indx,indy,indz) = prob(:,:,:,i); end
    Yp0b = Yb(indx,indy,indz); 
  end
  clear prob
  % mix Ymi with Yp0 map in case of AMAP mixing strategy (for non-T1 data) ... not working 
  if 0 %sum(Yrep(:))>0 && ~job.inv_weighting
    Yp0 = zeros(d,'single'); Yp0(indx,indy,indz) = Yp0b/3; 
    Yre = zeros(d,'single'); Yre(indx,indy,indz) = Yrep; 
    Ymi = Ymi .* (1-Yre) + Yre .* Yp0; clear Yre Yrep; 
  end



  %% -------------------------------------------------------------------
  %  Correction of WM hyperintensities
  %  -------------------------------------------------------------------
  %  The correction of WMH should be important for a correct normalization.
  %  It is only important to close the mayor WMH structures, and further
  %  closing can lead to problems with small gyri. So keep it simple here 
  %  and maybe add further refinements in the partitioning function.
  %  -------------------------------------------------------------------
  LAB  = job.extopts.LAB;
  Yp0 = zeros(d,'uint8'); Yp0(indx,indy,indz) = Yp0b; 
  qa.software.version_segment   = strrep(mfilename,'cat_main','');                            % if cat_main# save the # revision number 
  if isfield(res,'spmpp') && res.spmpp, qa.software.version_segment = 'SPM'; end                           % if SPM segmentation is used as input
  [cat_err_res.init.Yp0,cat_err_res.init.BB] = cat_vol_resize(Yp0,'reduceBrain',vx_vol,2,Yp0>0.5); 
  clear Ywmhrel Yp0
  


  % correction for normalization [and final segmentation]
  if ( (job.extopts.WMHC && job.extopts.WMHCstr>0) || job.extopts.SLC) && ~job.extopts.inv_weighting % && job.extopts.ignoreErrors < 2
    % display something
    %{
    if job.extopts.WMHC==1
      cat_io_cmd(sprintf('Internal WMH correction for spatial normalization')); % (WMHCstr=%0.2f)',job.extopts.WMHCstr));
    elseif job.extopts.WMHC>1
      cat_io_cmd(sprintf('Permanent WMH correction')); % (WMHCstr=%0.2f)',job.extopts.WMHCstr));
    end
    fprintf('\n'); 
    if job.extopts.SLC==1
      cat_io_cmd('Internal stroke lesion correction for spatial normalization'); 
    elseif job.extopts.SLC>1
      cat_io_cmd('Permanent stroke lesion correction');
    end
    fprintf('\n'); 
    %}
    
    % prepare correction map
    Ynwmh = NS(Yl1,LAB.TH) | NS(Yl1,LAB.BG) | NS(Yl1,LAB.HC) | NS(Yl1,LAB.CB) | NS(Yl1,LAB.BS);
    Ynwmh = cat_vol_morph(cat_vol_morph( Ynwmh, 'dd', 8 , vx_vol),'dc',12 , vx_vol) & ...
            ~cat_vol_morph( NS(Yl1,LAB.VT), 'dd', 4 , vx_vol); 
    Ywmh  = cat_vol_morph( Ycls{7}>0, 'dd', 1.5); 
    Ywmh  = Ycls{7}>0 | (~Ynwmh & (Ycls{2}==255 | ...
            cat_vol_morph( cat_vol_morph(Ycls{2}>128 | Ywmh,'ldc',1) ,'de' , 1.5)));
    Ywmh  = Ywmh .* cat_vol_smooth3X(Ywmh,0.5); % smooth inside

   
    %% transfer tissue from GM and CSF to WMH
    if job.extopts.SLC>0
      % WMHs and lesions
      if job.extopts.SLC==1
        Yls     = res.Ylesion; 
        Ycls{8} = cat_vol_ctype( Yls*255 ); 
      elseif job.extopts.SLC==2
        Yls     = NS(Yl1,LAB.LE)>0.5 | res.Ylesion; 
        Ycls{8} = cat_vol_ctype( Yls  .* single(Ycls{1})  +  Yls  .* single(Ycls{3})  + 255*single(res.Ylesion) ); 
      end
      Ycls{7} = cat_vol_ctype( Ywmh .* single(Ycls{1})  +  Ywmh .* single(Ycls{3}));
      Ycls{1} = cat_vol_ctype( single(Ycls{1}) .* (1 - Ywmh - single(Yls)) ); 
      Ycls{3} = cat_vol_ctype( single(Ycls{3}) .* (1 - Ywmh - single(Yls)) ); 
    else 
      % only WMHS
      Ycls{7} = cat_vol_ctype( Ywmh .* single(Ycls{1})  +  Ywmh .* single(Ycls{3}));
      Ycls{1} = cat_vol_ctype( single(Ycls{1}) .* (1 - Ywmh) ); 
      Ycls{3} = cat_vol_ctype( single(Ycls{3}) .* (1 - Ywmh) ); 
    end
    if ~debug, clear Ynwmh Ywmh Yls; end
    
    
    % different types of WMH correction as GM, WM or extra class
    % different types of lesion correction as CSF or extra class
    if numel(Ycls)>7 && job.extopts.SLC==1
      if job.extopts.WMHC<2
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*2/5 + single(Ycls{8})*1/5,'uint8');
      elseif job.extopts.WMHC==2 
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*3/5 + single(Ycls{8})*1/5,'uint8');
      elseif job.extopts.WMHC==3
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*4/5 + single(Ycls{8})*1/5,'uint8');
      end 
    elseif numel(Ycls)>7 && job.extopts.SLC==2
      if job.extopts.WMHC<2
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*2/5 + single(Ycls{8})*1.5/5,'uint8');
      elseif job.extopts.WMHC==2 
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*3/5 + single(Ycls{8})*1.5/5,'uint8');
      elseif job.extopts.WMHC==3
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*4/5 + single(Ycls{8})*1.5/5,'uint8');
      end 
    else % no stroke lesion handling
      if job.extopts.WMHC<2 
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*2/5,'uint8');
      elseif job.extopts.WMHC==2
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*3/5,'uint8');
      elseif job.extopts.WMHC==3
        Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5 + single(Ycls{7})*4/5,'uint8');
      end 
    end
    
  else
    Yp0b = cat_vol_ctype(single(Ycls{1})*2/5 + single(Ycls{2})*3/5 + single(Ycls{3})*1/5,'uint8');
  end
  
  % update error report structure
  [cat_err_res.init.Yp0,cat_err_res.init.BB] = cat_vol_resize(Yp0b,'reduceBrain',vx_vol,2,Yp0b>0.5); 
  
  % store smaller version
  Yp0b = Yp0b(indx,indy,indz); 
  clear Yclsb;

  if job.extopts.verb>2
    tpmci=tpmci+1; tmpmat = fullfile(pth,res.reportfolder,sprintf('%s_%s%02d%s.mat',nam,'write',tpmci,'preDartel'));
    save(tmpmat,'Yp0','Ycls','Ymi','T3th','vx_vol','Yl1');
    clear Yp0;
  end

else
%% SPM segmentation input  
%  ------------------------------------------------------------------------
%  Prepare data for registration and surface processing. 
%  We simply use the SPM segmentation as it is without further modelling of
%  a PVE or other refinements. 
%  ------------------------------------------------------------------------
  [Ym,Ymi,Yp0b,Yl1,Yy,YMF,indx,indy,indz,qa,job] = ...
    cat_main_SPMpp(Ysrc,Ycls,Yy,job,res);
  fprintf('%5.0fs\n',etime(clock,stime)); 
end



%% ---------------------------------------------------------------------
%  Spatial Registration with Dartel or Shooting
%  ---------------------------------------------------------------------
  if res.do_dartel
    Yclsd = Ycls(1:3); % use only GM and WM for deformation
    if job.extopts.WMHC>0 && numel(Ycls)>6
      Yclsd{2} = cat_vol_ctype(min(255,single(Ycls{2}) + single(Ycls{7}))); % set WMHs as WM in some cases
    end

    if job.extopts.SLC && isfield(res,'Ylesion') && sum(res.Ylesion(:)>0)
      % lesion detection in the original space with the original data
      LSstr   = 0.5; 
      Yvt     = cat_vol_morph( NS(Yl1,job.extopts.LAB.VT),'do',4,vx_vol);      % open to get lesions close to the ventricle
      Yvt     = cat_vol_morph( Yvt ,'dd',4,vx_vol);                            % add some voxels for smoothness
      res.Ylesion = cat_vol_ctype( single(res.Ylesion) .* (1 - (Yvt & Ym>0.9 & Ym<1.1) ));
      if ~debug, clear Yvt Ybgvt Ybgn;  end      
      % add lesion of automatic lesion estimation? - in development
      if job.extopts.WMHC>3
        res.Ylesion = cat_vol_ctype( single(res.Ylesion) + ...
          255* smooth3( Ym<1.5/3 & cat_vol_morph(NS(Yl1,job.extopts.LAB.LE),'dd',4*(1-LSstr))) ); 
      end
      Ylesions = cat_vol_smooth3X(single(res.Ylesion)/255,4); % final smoothing to have soft boundaries
    else
      Ylesions = zeros(size(Ym),'single'); 
    end
  
    % call Dartel/Shooting registration  
    if numel( job.extopts.vox ) > 1
      Yp0 = zeros(d,'single'); Yp0(indx,indy,indz) = single(Yp0b)/255*5; %job.export = 1; 
      [trans,res.ppe.reg] = cat_main_registration(job,res,Ycls,Yy,Ylesions,Yp0,Ym,Ymi,Yl1); clear Yp0; 
    else
      [trans,res.ppe.reg] = cat_main_registration(job,res,Yclsd,Yy,Ylesions);
    end
    clear Yclsd Ylesions;
  else
    if job.extopts.regstr == 0
      fprintf('Dartel registration is not required.\n');
    else
      fprintf('Shooting registration is not required.\n');
    end
  end
 
  
  
%% update WMHs 
%  ---------------------------------------------------------------------
  Ycls = cat_main_updateWMHs(Ym,Ycls,Yy,tpm,job,res,trans);
  if ~debug, clear Yy tpm; end


%% write results
%  ---------------------------------------------------------------------
Yp0 = zeros(d,'single'); Yp0(indx,indy,indz) = single(Yp0b)/255*5; 
cat_main_write(Ym,Ymi,Ycls,Yp0,Yl1,job,res,trans);
if 0 
  %% just for tests
  %  Write important maps with push and pull and resolution specific file names.  
  %  Report total tissue volumes in native and modulated warped space.
  Yp0    = zeros(d,'single'); Yp0(indx,indy,indz) = single(Yp0b)/255*5; 
  res2   = res; 
  job2   = job; 
  trans2 = trans;
  % write all maps
  job2.output.GM.warped     = 1; % test push/pull in general 
  job2.output.GM.mod        = 3; % test modulation of push/pull 
  job2.output.label.warped  = 1; % test general push/pull without modulation
  job2.output.bias.warped   = 1; % test general push/pull without modulation
  % write push for comparision 
  [pppush,ffpush,eepush]    = spm_fileparts(res2.image0.fname);
  res2.image0.fname         = fullfile(pppush,sprintf('%s%s%1.2f%s',ffpush,'-push',job.extopts.vox,eepush)); 
  trans2.warped.push        = 1; 
  trans2.warped.verb        = 1; 
  cat_main_write(Ym,Ymi,Ycls,Yp0,Yl1,job2,res2,trans2);
  % write pull for comparision 
  res2.image0.fname         = fullfile(pppush,sprintf('%s%s%1.2f%s',ffpush,'-pull',job.extopts.vox,eepush)); 
  trans2.warped.push        = 0; 
  cat_main_write(Ym,Ymi,Ycls,Yp0,Yl1,job2,res2,trans2);
  clear res2 job2 trans2;
end
if ~debug, clear Yp0; end


%% surface creation and thickness estimation
%  ---------------------------------------------------------------------
if all( [job.output.surface>0 job.output.surface<9 ] ) || (job.output.surface==9 && ...
   any( [job.output.ct.native job.output.ct.warped job.output.ct.dartel job.output.ROI] ))
  
  % prepare some parameter
  Yp0 = zeros(d,'single'); Yp0(indx,indy,indz) = single(Yp0b)*5/255; 
  [Ymix,job,surf,WMT] = cat_main_surf_preppara(Ymi,Yp0,job,vx_vol);
  
  if job.extopts.pbtres==99 
  % development block with manual settings
    smeth = [3 1]; 
    sres  = [1 0.5]; % internal pbtres
    surf = {'lhfst'}; %,'lcfst','rhfst','rcfst'};  
    for smi = 1:numel(smeth)
      for sresi = 1:numel(sres)
        %% new pipelines and test
        if smeth(smi)==1, pbtmethod = 'pbt2xf'; elseif smeth(smi)==3, pbtmethod = 'pbt3'; end
        cat_io_cprintf('blue',sprintf('\nPBT Test99 - surf_%s_%0.2f\n',pbtmethod,sres(sresi)));
        [Yth1,S,Psurf,qa.subjectmeasures.EC_abs,qa.subjectmeasures.defect_size] = ...
          cat_surf_createCS(VT,VT0,Ymix,Yl1,Yp0/3,YMF,struct('pbtmethod',pbtmethod,...
          'interpV',sres(sresi),'Affine',res.Affine,'surf',{surf},...
          'inv_weighting',job.extopts.inv_weighting,'verb',job.extopts.verb,'WMT',WMT,...
          'useprior',job.useprior)); 
      end
    end
  else
  %% default surface reconstruction 
  %  sum(Yth1(Yth1(:)>median(Yth1(Yth1(:)>0))*2 ))./sum(Yth1(Yth1(:)>0)) > 0.1 > error
    if job.extopts.SRP >= 20
      surf = unique(surf,'stable'); 
      if 0 %any( ~cellfun('isempty', strfind(surf,'cb') ))  % ... I want to avoid this if possible - it also seem to be worse to use it 
        VT1 = spm_vol(cat_get_defaults('extopts.shootingT1')); 
        fac = abs(tpm.V(1).mat(1)) / abs(VT1.mat(1));
        YT  = single(spm_sample_vol(VT1,double(smooth3(Yy(:,:,:,1))*fac),double(smooth3(Yy(:,:,:,2))*fac),double(smooth3(Yy(:,:,:,3))*fac),2));
        YT  = reshape(YT,size(Yy(:,:,:,1))); clear Yyi; 
      else
        YT  = [];
      end
      %% further GUI fields ...
      if ~isfield(job.extopts,'vdist'),           job.extopts.vdist           = 0;  end
      if ~isfield(job.extopts,'scale_cortex'),    job.extopts.scale_cortex    = cat_get_defaults('extopts.scale_cortex'); end
      if ~isfield(job.extopts,'add_parahipp'),    job.extopts.add_parahipp    = cat_get_defaults('extopts.add_parahipp'); end
      if ~isfield(job.extopts,'close_parahipp'),  job.extopts.close_parahipp  = cat_get_defaults('extopts.close_parahipp'); end
      if ~isfield(job.extopts,'pbtmethod'),       job.extopts.pbtmethod       = cat_get_defaults('extopts.pbtmethod'); end
      if ~isfield(job.extopts,'reduce_mesh'),     job.extopts.reduce_mesh     = 1; end % cat_get_defaults('extopts.reduce_mesh'); end
      %if ~isfield(job.output,'pp'),               job.output.pp               = struct('native',0,'warped',0,'dartel',0);  end % this is now in defaults and not required here 
      if ~isfield(job.output,'surf_measures'),    job.output.surf_measures    = 1; end % developer
      
      if job.extopts.SRP >= 30
        [Yth1, S, Psurf, qa.createCS] = ...
          cat_surf_createCS3(VT,VT0,Ymix,Yl1,YMF,YT,struct('trans',trans,'reduce_mesh',job.extopts.reduce_mesh,... required for Ypp output
          'outputpp',job.output.pp,'surf_measures',job.output.surf_measures, ...
          'interpV',job.extopts.pbtres,'pbtmethod',job.extopts.pbtmethod,...
          'scale_cortex', job.extopts.scale_cortex, 'add_parahipp', job.extopts.add_parahipp, 'close_parahipp', job.extopts.close_parahipp,  ....
          'Affine',res.Affine,'surf',{surf},'pbtlas',job.extopts.pbtlas, ... % pbtlas is the new parameter to reduce myelination effects
          'inv_weighting',job.inv_weighting,'verb',job.extopts.verb,'useprior',job.useprior),job); 
        qa.subjectmeasures.EC_abs = NaN;
        qa.subjectmeasures.defect_size = NaN;
      else
        [Yth1, S, Psurf, qa.subjectmeasures.EC_abs, qa.subjectmeasures.defect_size, qa.createCS] = ...
          cat_surf_createCS2(VT,VT0,Ymix,Yl1,YMF,YT,struct('trans',trans,'reduce_mesh',job.extopts.reduce_mesh,... required for Ypp output
          'vdist',job.extopts.vdist,'outputpp',job.output.pp,'surf_measures',job.output.surf_measures, ...
          'interpV',job.extopts.pbtres,'pbtmethod',job.extopts.pbtmethod,'SRP',mod(job.extopts.SRP,10),...
          'scale_cortex', job.extopts.scale_cortex, 'add_parahipp', job.extopts.add_parahipp, 'close_parahipp', job.extopts.close_parahipp,  ....
          'Affine',res.Affine,'surf',{surf},'pbtlas',job.extopts.pbtlas, ... % pbtlas is the new parameter to reduce myelination effects
          'inv_weighting',job.inv_weighting,'verb',job.extopts.verb,'WMT',WMT,'useprior',job.useprior),job); 
      end
    else
      %%
      [Yth1,S,Psurf,qa.subjectmeasures.EC_abs,qa.subjectmeasures.defect_size, qa.createCS] = ...
        cat_surf_createCS(VT,VT0,Ymix,Yl1,YMF,struct('pbtmethod','pbt2x',...
        'interpV',job.extopts.pbtres,'extract_pial_white',mod(job.extopts.SRP,10), ...
        'Affine',res.Affine,'surf',{surf},'pbtlas',job.extopts.pbtlas, ... % pbtlas is the new parameter to reduce myelination effects
        'inv_weighting',job.extopts.inv_weighting,'verb',job.extopts.verb,'WMT',WMT,'useprior',job.useprior),job); 
    end
  end
  
  % thickness map
  if numel(fieldnames(S))==0 && isempty(Psurf), clear S Psurf; end
  if isfield(job.output,'ct')
    cat_io_writenii(VT0,Yth1,res.mrifolder,'ct','cortical thickness map','uint16',...
      [0,0.0001],job.output.ct,trans,single(Ycls{1})/255,0.1);
  end
  
  if job.output.sROI && all(job.output.surface~=[5 6]) % no fast without registration
    cat_io_cmd('  Surface ROI estimation');  
    
    %% estimate surface ROI estimates for thickness
    [pp,ff]   = spm_fileparts(VT.fname);
    [stat, val] = fileattrib(pp);
    if stat, pp = val.Name; end

    [mrifolder, reportfolder, surffolder] = cat_io_subfolders(VT.fname);

    if cat_get_defaults('extopts.subfolders') && strcmp(mrifolder,'mri')
      pp = spm_str_manip(pp,'h'); % remove 'mri' in pathname that already exists
    end
    surffolder = fullfile(pp,surffolder);

    % get original filename without 'n'
    [pp0,ff]   = spm_fileparts(VT0.fname);
    
    Psatlas_lh   = job.extopts.satlas(  [job.extopts.satlas{:,4}]>0 , 2);
    Pthick_lh    = cell(1,1);
    Pthick_lh{1} = fullfile(surffolder,sprintf('lh.thickness.%s',ff));
    
    cat_surf_surf2roi(struct('cdata',{{Pthick_lh}},'rdata',{Psatlas_lh}));

    fprintf('%5.0fs\n',etime(clock,stime2));
  end
  
  cat_io_cmd('Surface and thickness estimation takes');  
  fprintf('%5.0fs\n',etime(clock,stime));
  if ~debug; clear YMF Yp0; end
  if ~debug && ~job.output.ROI && job.output.surface, clear Yth1; end
  
  
else
  %if ~debug; clear Ymi; end
end



%% ROI data extraction 
%  ---------------------------------------------------------------------
%  This part estimates individual measurements for different ROIs.
%  The ROIs are described in the CAT normalized space and there are two 
%  ways to estimate them - (1) in subject space, and (2) in normalized 
%  space. Estimation in normalized space is more direct and avoids further
%  transformations. The way over the subject space has the advantage 
%  that individual anatomical refinements are possible, but this has
%  to be done and evaluated for each atlas. 
%  Test call (type: 1-native,2-push,3-pull*; write: 1-verb,2-imgs):
%     cat_main_roi(job,trans,Ycls,Yp0,struct('type',1,'write',1)); 
%  ---------------------------------------------------------------------
if job.output.ROI  
  try
    Yp0 = zeros(d,'single'); Yp0(indx,indy,indz) = single(Yp0b)/255*5; 
    cat_main_roi(job,trans,Ycls,Yp0); 
  catch
    cat_io_addwarning([mfilename ':cat_main_roi'],'Error in cat_main_roi.',1,[1 1]);
  end
end
if ~debug, clear wYp0 wYcls wYv Yp0; end



%% XML-report and Quality Control
%  ---------------------------------------------------------------------
%  RD20200725: evaluate difference between res.Affine and res.Affine0
%              create error for too strong differences

%  estimate brain tissue volumes and TIV
qa.subjectmeasures.vol_abs_CGW = [
  prod(vx_vol)/1000/255 .* sum(Ycls{3}(:)),      ... CSF
  prod(vx_vol)/1000/255 .* sum(Ycls{1}(:)),      ... GM 
  prod(vx_vol)/1000/255 .* sum(Ycls{2}(:)) 0 0];   % WM WMHs SL
qa.subjectmeasures.vol_abs_WMH = 0;                % RD202011: just for internal use (cat_report) but ok if people see it  
qa.subjectmeasures.vol_rel_WMH = 0;  
% stroke lesions
if numel(Ycls)>7, qa.subjectmeasures.vol_abs_CGW(5) = prod(vx_vol)/1000/255 .* sum(Ycls{8}(:)); end 
% set WMHs
if numel(Ycls)>6 && numel(Ycls{6})>0
  qa.subjectmeasures.vol_abs_WMH = prod(vx_vol)/1000/255 .* sum(Ycls{7}(:));
  if job.extopts.WMHC > 2       % extra class
    qa.subjectmeasures.vol_abs_CGW(4) = prod(vx_vol)/1000/255 .* sum(Ycls{7}(:));
  elseif job.extopts.WMHC == 2  % count as WM
    qa.subjectmeasures.vol_abs_CGW(2) = qa.subjectmeasures.vol_abs_CGW(2) + prod(vx_vol)/1000/255 .* sum(Ycls{7}(:));
  else                          % count as GM
    qa.subjectmeasures.vol_abs_CGW(1) = qa.subjectmeasures.vol_abs_CGW(1) + prod(vx_vol)/1000/255 .* sum(Ycls{7}(:));
  end
  qa.subjectmeasures.vol_rel_WMH = qa.subjectmeasures.vol_abs_WMH ./ sum(qa.subjectmeasures.vol_abs_CGW);
end
if job.output.surface && isfield(S,'lh') && isfield(S,'rh')
  qa.subjectmeasures.surf_TSA    =  sum( cat_surf_fun('area',S.lh) )/100 + sum( cat_surf_fun('area',S.lh) )/100; 
end
qa.subjectmeasures.vol_TIV     =  sum(qa.subjectmeasures.vol_abs_CGW); 
qa.subjectmeasures.vol_rel_CGW =  qa.subjectmeasures.vol_abs_CGW ./ qa.subjectmeasures.vol_TIV;
if ~debug, clear Ycls; end
if job.output.surface
  qa.qualitymeasures.SurfaceEulerNumber       = qa.subjectmeasures.EC_abs;
  qa.qualitymeasures.SurfaceDefectArea        = qa.subjectmeasures.defect_size;
  qa.qualitymeasures.SurfaceDefectNumber      = qa.createCS.defects;
  qa.qualitymeasures.SurfaceIntensityRMSE     = qa.createCS.RMSE_Ym;
  qa.qualitymeasures.SurfacePositionRMSE      = qa.createCS.RMSE_Ypp;
  if isfield(qa,'createCS') && isfield(qa.createCS,'self_intersections')
    qa.qualitymeasures.SurfaceSelfIntersections = qa.createCS.self_intersections;
  else
    qa.qualitymeasures.SurfaceSelfIntersections = []; 
  end
end
stime = cat_io_cmd('Quality check'); job.stime = stime; 
Yp0   = zeros(d,'single'); Yp0(indx,indy,indz) = single(Yp0b)/255*5; Yp0(Yp0>3.1) = nan; % no analysis in WMH regions
% in case of SPM input segmentation we have to add the name here to have a clearly different naming of the CAT output 
if isfield(res,'spmpp') && res.spmpp, namspm = 'c1'; else, namspm = ''; end
qa    = cat_vol_qa('cat12',Yp0,VT0.fname,Ym,res,job.extopts.species, ...
          struct('write_csv',0,'write_xml',1,'method','cat12','job',job,'qa',qa,'prefix',['cat_' namspm]));
clear Yp0;
    
% surface data update
if job.output.surface
  if exist('S','var')
    if isfield(S,'lh') && isfield(S.lh,'th1'), th=S.lh.th1; else, th=[]; end
    if isfield(S,'rh') && isfield(S.rh,'th1'), th=[th; S.rh.th1]; end
    qa.subjectmeasures.dist_thickness{1} = [cat_stat_nanmean(th(:)) cat_stat_nanstd(th(:))]; 
    
    if job.extopts.expertgui>1
      if isfield(S,'lh') && isfield(S.lh,'th2'), th2=S.lh.th2; else, th2=[]; end 
      if isfield(S,'rh') && isfield(S.lh,'th2'), th2=[th2; S.rh.th2]; end
      qa.subjectmeasures.dist_gyruswidth{1} = [cat_stat_nanmean(th2(:)) cat_stat_nanstd(th2(:))]; 
      if isfield(S,'lh') && isfield(S.lh,'th3'), th2=S.lh.th3; else, th2=[]; end 
      if isfield(S,'rh') && isfield(S.lh,'th3'), th2=[th2; S.rh.th3]; end
      qa.subjectmeasures.dist_sulcuswidth{1} = [cat_stat_nanmean(th2(:)) cat_stat_nanstd(th2(:))];
    end
  elseif exist('Yth1','var')
    qa.subjectmeasures.dist_thickness{1} = [cat_stat_nanmean(Yth1(Yth1(:)>1)) cat_stat_nanstd(Yth1(Yth1(:)>1))];
    th = Yth1(Yth1(:)>1); 
    % gyrus- and sulcus-width? 
  end
  %% Thickness peaks 
  %  Estimation of kmean peaks to describe the thickess in a better way than
  %  by using only mean and std that are both biased strongly by outliers.
  [thm ,ths, thh ] = cat_stat_kmeans( th , 1 );  % one anatomical average peak
  [thma,thsa,thha] = cat_stat_kmeans( th( abs( th - thm ) < ths * 2 ) , 3 ); % 3 anatomical peaks
  [thme,thse,thhe] = cat_stat_kmeans( th( (th < thma(1) - 2*thsa(1) ) |  (th > thma(end) + 2*thsa(end) )) , 2 ); % 3 anatomical peaks
  qa.subjectmeasures.dist_thickness_kmeans        = [thm'  ths'  thh' ]; 
  qa.subjectmeasures.dist_thickness_kmeans_inner3 = [thma' thsa' thha']; 
  qa.subjectmeasures.dist_thickness_kmeans_outer2 = [thme' thse' thhe']; 
  clear th; 
   
  %qam = cat_stat_marks('eval',job.cati,qa,'cat12'); % ... not ready
  cat_io_xml(fullfile(pth,res.reportfolder,['cat_' namspm nam '.xml']),struct(...
    ... 'subjectratings',qam.subjectmeasures, ... not ready
    'subjectmeasures',qa.subjectmeasures,'ppe',res.ppe),'write+'); % here we have to use the write+!
end
fprintf('%5.0fs\n',etime(clock,stime));
clear Yth1;

if qa.subjectmeasures.vol_rel_WMH>0.01 && job.extopts.WMHC<2
  cat_io_addwarning([mfilename ':uncorrectedWMHs'],...
    sprintf('Uncorrected WM lesions greater (%2.2f%%%%%%%% of the TIV, %2.2f%%%%%%%% of the WM)!',...
    qa.subjectmeasures.vol_rel_WMH * 100, ...
    qa.subjectmeasures.vol_abs_WMH / qa.subjectmeasures.vol_abs_CGW(3) * 100),1);
end




%% CAT reports
%  ---------------------------------------------------------------------
%  Final report of preprocessing parameter and results in the SPM 
%  graphics window that is exported as PDF/JPG. The parameter were
%  combined in cat_main_reportstr to three text strings that were 
%  printed in combination with volume (spm_orthviews) and surface 
%  data (cat_surf_display). The processing is finished by some 
%  lines in the command line window.
%  ---------------------------------------------------------------------
if job.extopts.print
  %%
  str = cat_main_reportstr(job,res,qa);
  Yp0 = zeros(d,'single'); Yp0(indx,indy,indz) = single(Yp0b)/255*5; 
  if ~exist('Psurf','var'), Psurf = ''; end
  cat_main_reportfig(Ymi,Yp0,Yl1,Psurf,job,qa,res,str);
end

% final command line report
cat_main_reportcmd(job,res,qa);
%%
%% cleanup fast
try
  delete_surf_preview(Psurf,job);
end
return

function delete_surf_preview(Psurf,job)
  % cleanup preview surfaces and directory (but only for non-experts)
  if any( job.output.surface == [ 5 6 ] ) && job.extopts.expertgui<1
    % delete files that where possibly created in cat_surf_createCS(2)
 
% RD202101: not all files are listed ... further lh.*.preview.* files: 
%           - intlayer4, intpial, intwhite
%           - layer4, pial, white

    ffields = fieldnames(Psurf); 
    for si = 1:numel( Psurf )
      for fi = 1:numel( ffields )
        [pp1,pp2] = spm_fileparts( spm_fileparts( Psurf(si).(ffields{fi}) ) );  
        if exist( Psurf(si).(ffields{fi}) , 'file' ) && strcmp(pp2,'surf_preview') 
          delete( Psurf(si).(ffields{fi}) ); 
        end
      end
    end
    
    % remove the directory 
    % (but only if it is empty (maybe used by parallel processes)
    pp        = spm_fileparts( Psurf(1).Pcentral ); 
    [pp1,pp2] = spm_fileparts( pp );  
    dcontent  = dir( pp ); 
    if exist( pp , 'dir' ) &&  strcmp(pp2,'surf_preview') && ...
      numel( dcontent( [dcontent.isdir] == 0) ) == 0
      try
        rmdir( pp , 's');
      end
    end
    % check also for an empty surf directory
    if exist( pp , 'dir' ) &&  strcmp(pp2,'surf') && ...
      numel( dcontent( [dcontent.isdir] == 0) ) == 0
      try
        rmdir( fullfile(pp,'surf') , 's');
      end
    end
  end
return
function [Ysrc,Ycls,Yy,res] = cat_main_resspmres(Ysrc,Ycls,Yy,res)
%% cat_main_resspmres
%  ---------------------------------------------------------------------
%  Interpolate to internal resolution if lower resultion was used for 
%  SPM preprocessing
%
%    [Ysrc,Ycls,Yy,res] = cat_main_resspmres(Ysrc,Ycls,Yy,res)
%
%  ---------------------------------------------------------------------

  % Update Ycls: cleanup on original data
  Yb = Ycls{1} + Ycls{2} + Ycls{3}; 
  for i=1:numel(Ycls)
    [Pc(:,:,:,i),BB] = cat_vol_resize(Ycls{i},'reduceBrain',repmat(job.opts.redspmres,1,3),2,Yb); %#ok<AGROW>
  end 
  Pc = cat_main_clean_gwc(Pc,1);
  for i=1:numel(Ycls), Ycls{i} = cat_vol_resize(Pc(:,:,:,i),'dereduceBrain',BB); end; clear Pc Yb; 
  for ci=1:numel(Ycls)
    Ycls{ci} = cat_vol_ctype(cat_vol_resize(Ycls{ci},'deinterp',res.redspmres,'linear'));
  end

  % Update Yy:
  Yy2 = zeros([res.redspmres.sizeO 3],'single');
  for ci=1:size(Yy,4)
    Yy2(:,:,:,ci) = cat_vol_ctype(cat_vol_resize(Yy(:,:,:,ci),'deinterp',res.redspmres,'linear'));
  end
  Yy   = Yy2; clear Yy2; 

  % Update Ysrc:
  Ysrc = cat_vol_resize(Ysrc,'deinterp',res.redspmres,'cubic');
  Ybf  = res.image1.dat ./ Ysrc; 
  Ybf  = cat_vol_approx(Ybf .* (Ysrc~=0 & Ybf>0.25 & Ybf<1.5),'nn',1,8);
  Ysrc = res.image1.dat ./ Ybf; clear Ybf; 
  res.image = res.image1; 
    res  = rmfield(res,'image1');
return

function [res,job,VT,VT0,pth,nam,vx_vol,d] = cat_main_updatepara(res,tpm,job)
%% Update parameter
%  ---------------------------------------------------------------------
%  Update CAT/SPM parameter variable job and the SPM preprocessing 
%  variable res
%
%    [res,job] = cat_main_updatepara(res,job)
%
%  ---------------------------------------------------------------------

  % this limits ultra high resolution data, i.e. images below ~0.4 mm are reduced to ~0.7mm! 
  % used in cat_main_partvol, cat_main_gcut, cat_main_LAS
  def.extopts.uhrlim  = 0.7 * 2; % default 0.7*2 that reduce images below 0.7 mm
  def.cati            = 0;
  def.color.error     = [0.8 0.0 0.0];
  def.color.warning   = [0.0 0.0 1.0];
  def.color.warning   = [0.8 0.9 0.3];
  def.color.highlight = [0.2 0.2 0.8];
  job = cat_io_checkinopt(job,def);

  clear def; 

  % complete job structure
  defr.ppe = struct(); 
  res = cat_io_checkinopt(res,defr);


  % definition of subfolders - add to res variable?
  [res.mrifolder, res.reportfolder, res.surffolder, res.labelfolder] = cat_io_subfolders(res.image0(1).fname,job);

  % Sort out bounding box etc
  res.bb = spm_get_bbox(tpm.V(1)); 


  if numel(res.image) > 1
    warning('CAT12:noMultiChannel',...
      'CAT12 does not support multiple channels. Only the first channel will be used.');
  end

  % use dartel (do_dartel=1) or shooting (do_dartel=2) normalization
  res.do_dartel = 1 + (job.extopts.regstr(1)~=0);      
  if res.do_dartel
    tc = [cat(1,job.tissue(:).native) cat(1,job.tissue(:).warped)]; 
    need_dartel = any(job.output.warps) || ...
      job.output.bias.warped || ...
      job.output.label.warped || ...
      any(any(tc(:,[4 5 6]))) || job.output.jacobian.warped || ...
      job.output.ROI || ...
      any([job.output.atlas.warped]) || ...
      numel(job.extopts.regstr)>1 || ...
      numel(job.extopts.vox)>1;
    if ~need_dartel
      res.do_dartel = 0;
    end
  end
  
  % Update templates for LAS
  if res.do_dartel<2 && job.extopts.regstr(1) == 0
    job.extopts.templates = job.extopts.darteltpms; 
  else
    job.extopts.templates = job.extopts.shootingtpms; 
  end 
  
  % remove noise/interpolation prefix
  VT  = res.image(1);  % denoised/interpolated n*.nii
  VT0 = res.image0(1); % original 
  [pth,nam] = spm_fileparts(VT0.fname); 

  % voxel size parameter
  vx_vol     = sqrt(sum(VT.mat(1:3,1:3).^2));    % voxel size of the processed image
  res.vx_vol = vx_vol; 
  
  % delete old xml file 
  oldxml = fullfile(pth,res.reportfolder,['cat_' nam '.xml']);  
  if exist(oldxml,'file'), delete(oldxml); end
  clear oldxml

  d = VT.dim(1:3);

return

function [Ycls,Ym,Ymi,Yp0b,Yl1,Yy,YMF,indx,indy,indz,qa,job] = cat_main_SPMpp(Ysrc,Ycls,Yy,job,res)
%% SPM segmentation input  
%  ------------------------------------------------------------------------
%  Here, DARTEL and PBT processing is prepared. 
%  We simply use the SPM segmentation as it is, without further modelling 
%  of the partial volume effect or other refinements. 
%  ------------------------------------------------------------------------
  
  NS = @(Ys,s) Ys==s | Ys==s+1;         % for side independent atlas labels
  
  % QA WMH values required by cat_vol_qa later
  qa.subjectmeasures.WMH_abs    = nan;  % absolute WMH volume without PVE
  qa.subjectmeasures.WMH_rel    = nan;  % relative WMH volume to TIV without PVE
  qa.subjectmeasures.WMH_WM_rel = nan;  % relative WMH volume to WM without PVE
  qa.subjectmeasures.WMH_abs    = nan;  % absolute WMH volume without PVE in cm^3

  vx_vol  = sqrt(sum(res.image(1).mat(1:3,1:3).^2));  

  %% Update Ycls: cleanup on original data
  Yb = Ycls{1} + Ycls{2} + Ycls{3}; 
  for i=1:numel(Ycls)
    [Pc(:,:,:,i),BB] = cat_vol_resize(Ycls{i},'reduceBrain',repmat(job.opts.redspmres,1,3),2,Yb); %#ok<AGROW>
  end 
  Pc = cat_main_clean_gwc(Pc,round(1./mean(vx_vol)),2);
  for i=1:3, Ycls{i} = cat_vol_resize(Pc(:,:,:,i),'dereduceBrain',BB); end; clear Pc Yb; 
 
  %% Update Ycls: cleanup on original data
  if numel(Ycls)==3
    % in post-mortem data there is no CSF and CSF==BG
    Yb     = Ycls{1} + Ycls{2}; 
    [Yb,R] = cat_vol_resize(single(Yb),'reduceV',vx_vol,1,32,'meanm');     % use lower resolution to save time 
    Yb     = cat_vol_morph(Yb>128,'ldo',3,R.vx_volr);                      % do some cleanup 
    Yb     = cat_vol_morph(Yb,'ldc',8,R.vx_volr);                          % close mask (even large ventricles)
    Yb     = cat_vol_morph(Yb,'dd',1,R.vx_volr);                           % add 1 mm to have some CSF around the brain and simpliefy PVEs
    Yb     = cat_vol_resize(smooth3(Yb),'dereduceV',R)>0.5;                % reinterpolate image and add some space around it
    
    Ycls{3} = cat_vol_ctype(single(Ycls{3}) .* Yb); 
    Ycls{4} = cat_vol_ctype(255 * (1-Yb));
  else
    Yb = Ycls{1} + Ycls{2} + Ycls{3}; 
  end
  for i=1:numel(Ycls)
    [Pc(:,:,:,i),BB] = cat_vol_resize(Ycls{i},'reduceBrain',repmat(job.opts.redspmres,1,3),2,Yb);
  end 
  Pc = cat_main_clean_gwc(Pc,round(1./mean(vx_vol)),2);
  for i=1:3, Ycls{i} = cat_vol_resize(Pc(:,:,:,i),'dereduceBrain',BB); end; clear Pc Yb; 
  
  %% create (resized) label map and brainmask
  Yp0  = single(Ycls{3})/5 + single(Ycls{1})/5*2 + single(Ycls{2})/5*3;
  Yb   = Yp0>0.5;
  
  % load original images and get tissue thresholds
  clsint = @(x) round( sum(res.mn(res.lkp==x) .* res.mg(res.lkp==x)') * 10^5)/10^5;
  %Ysrc = spm_read_vols(spm_vol(fullfile(pp,[ff ee])));
  WMth = double(max(clsint(2),...
           cat_stat_nanmedian(cat_stat_nanmedian(cat_stat_nanmedian(Ysrc(Ycls{2}>192)))))); 
  T3th = [ min([  clsint(1) - diff([clsint(1),WMth]) ,clsint(3)]) , clsint(2) , WMth];
  clear Ysrc
  
  job.extopts.WMHC          = 0;
  job.extopts.SLC           = 0;
  job.extopts.LASmyostr     = 0; 
  job.extopts.inv_weighting = T3th(3)<T3th(2);
  job.inv_weighting         = T3th(3)<T3th(2);
  job.useprior              = '';
  
  % the intensity normalized images are here represented by the segmentation 
  Ym   = Yp0/255*5/3;
  Ymi  = Yp0/255*5/3; 
   
  % low resolution Yp0b
  sz = size(Yb);
  [indx, indy, indz] = ind2sub(sz,find(Yb>0));
  indx = max((min(indx) - 1),1):min((max(indx) + 1),sz(1));
  indy = max((min(indy) - 1),1):min((max(indy) + 1),sz(2));
  indz = max((min(indz) - 1),1):min((max(indz) + 1),sz(3));
  Yp0b = Yp0(indx,indy,indz);
  clear Yp0 Yb; 
  
  % load atlas map and prepare filling mask YMF
  % compared to CAT default processing, we have here the DARTEL mapping, but no individual refinement 
  Vl1 = spm_vol(job.extopts.cat12atlas{1});
  Yl1 = cat_vol_ctype(spm_sample_vol(Vl1,double(Yy(:,:,:,1)),double(Yy(:,:,:,2)),double(Yy(:,:,:,3)),0));
  Yl1 = reshape(Yl1,size(Ym)); [D,I] = cat_vbdist(single(Yl1>0)); Yl1 = Yl1(I);   
  YMF = NS(Yl1,job.extopts.LAB.VT) | NS(Yl1,job.extopts.LAB.BG) | NS(Yl1,job.extopts.LAB.BG);  
return

function [Ymix,job,surf,WMT,stime] = cat_main_surf_preppara(Ymi,Yp0,job,vx_vol)
%  ------------------------------------------------------------------------
%  Prepare some variables for the surface processing.
%  ------------------------------------------------------------------------

  stime = cat_io_cmd('Surface and thickness estimation'); 
  
  % specify WM/CSF width/depth/thickness estimation
  if job.output.surface>10
    job.output.surface = job.output.surface - 10;
    WMT = 1; 
  elseif job.extopts.experimental || job.extopts.expertgui==2
    WMT = 1; 
  else
    WMT = 0; 
  end
  
  % specify surface
  switch job.output.surface
    case 1, surf = {'lh','rh'};
    case 2, surf = {'lh','rh','cb'};
    case 3, surf = {'lh'};
    case 4, surf = {'rh'};
    % fast surface reconstruction without simple spherical mapping     
    case 5, surf = {'lhfst','rhfst'};                   
    case 6, surf = {'lhfst','rhfst','cbfst'}; 
    % fast surface reconstruction with simple spherical mapping     
    case 7, surf = {'lhsfst','rhsfst'};                    
    case 8, surf = {'lhsfst','rhsfst','cbsfst'};
    % estimate only volumebased thickness
    case 9, surf = {'lhv','rhv'}; 
    otherwise, surf = {};
  end
  if ~job.output.surface && any( [job.output.ct.native job.output.ct.warped job.output.ct.dartel] )
    surf = {'lhv','rhv'}; 
  end
  
  % lower resolution for fast surface estimation
  if job.output.surface>4 && job.output.surface~=9 
    try
      if strcmp(job.extopts.species,'human')
        job.extopts.pbtres = max(0.8,min([((min(vx_vol)^3)/2)^(1/3) 1.0]));
      else
        job.extopts.pbtres = max(0.4,min([((min(vx_vol)^3)/2)^(1/3) 1.0]));
      end
    catch
      job.extopts.pbtres = max(0.8,min([((min(vx_vol)^3)/2)^(1/3) 1.0]));
    end
  end
  
  % surface creation and thickness estimation (only for test >> manual setting)
  Yp0toC = @(c) 1-min(1,abs(Yp0-c));
  Yp0th  = @(c) cat_stat_nanmedian( Ymi(Yp0toC(c) > 0.5) ); 
  if ( Yp0th(1) < Yp0th(2) ) && ( Yp0th(2) < Yp0th(3) ) && ( Yp0th(3) > 0.9 ) % if T1
    Ymix = Ymi .* (Yp0>0.5); % | (cat_vol_morph(Yp0>0.5,'d') & Ymi<2/3)); %% using the Ymi map
  %elseif  ( Yp0th(1) > Yp0th(2) ) && ( Yp0th(2) > Yp0th(3) ) % if T1
  %  Ymix = (4/3 - Ymi) .* (Yp0>0.5);
  else % use only the segmentation map if any other contrast (or for tests)
    Ymix = Yp0 / 3;  
  end
return
