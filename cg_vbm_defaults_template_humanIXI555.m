function cat_defaults_template_humanIXI555
% Sets the defaults for VBM
% FORMAT cat_defaults
%_______________________________________________________________________
%
% This file is intended to be customised for the site.
%
% Care must be taken when modifying this file
%_______________________________________________________________________
% $Id$

global cat

% important fields of the animal version
%=======================================================================
% - cat.opts.tpm 
% - cat.extopts.darteltpm
% - cat.extopts.cat12atlas
% - cat.extopts.brainmask
% - cat.extopts.bb         > [-inf -inf -inf; inf inf inf] 
% - cat.extopts.vox        > inf
% - cat.opts.affreg        > subj
% - cat.opts.biasreg       > 0.00001
% - cat.opts.biasfwhm      > 40
% - cat.opts.samp          > 2 mm
%=======================================================================


% Estimation options
%=======================================================================
cat.opts.tpm       = {fullfile(spm('dir'),'tpm','TPM.nii')};
cat.opts.ngaus     = [3 3 2 3 4 2];           % Gaussians per class    - 3 GM and 3 WM classes for robustness
cat.opts.affreg    = 'mni';                   % Affine regularisation  - '';'mni';'eastern';'subj';'none';'rigid';
cat.opts.warpreg   = [0 0.001 0.5 0.05 0.2];  % Warping regularisation - see Dartel instructions
cat.opts.biasreg   = 0.0001;                  % Bias regularisation    - smaller values for stronger bias fields
cat.opts.biasfwhm  = 60;                      % Bias FWHM              - lower values for stronger bias fields, but check for overfitting in subcortical GM (values <50 mm)
cat.opts.samp      = 2;                       % Sampling distance      - smaller 'better', but slower - maybe useful for >= 7 Tesla 

                                              
% Writing options
%=======================================================================

% options:
%   native    0/1     (none/yes)
%   warped    0/1     (none/yes)
%   mod       0/1/2   (none/affine+nonlinear/nonlinear only)
%   dartel    0/1/2   (none/rigid/affine)
%   affine    0/1     (none/affine)

% save surface and thickness
cat.output.surface     = 0;     % surface and thickness creation

% save ROI values
cat.output.ROI         = 2;     % write csv-files with ROI data: 1 - subject space; 2 - normalized space; 3 - both (default 2)

% bias and noise corrected, (locally - if LAS>0) intensity normalized
cat.output.bias.native = 0;
cat.output.bias.warped = 1;
cat.output.bias.affine = 0;

% GM tissue maps
cat.output.GM.native  = 0;
cat.output.GM.warped  = 0;
cat.output.GM.mod     = 2;
cat.output.GM.dartel  = 0;

% WM tissue maps
cat.output.WM.native  = 0;
cat.output.WM.warped  = 0;
cat.output.WM.mod     = 2;
cat.output.WM.dartel  = 0;
 
% CSF tissue maps
cat.output.CSF.native = 0;
cat.output.CSF.warped = 0;
cat.output.CSF.mod    = 0;
cat.output.CSF.dartel = 0;

% WMH tissue maps (only for opt.extopts.WMHC==3) - in development
% no modulation available, due to the high spatial variation of WMHs
cat.output.WMH.native  = 0;
cat.output.WMH.warped  = 0;
cat.output.WMH.dartel  = 0;

% label 
% background=0, CSF=1, GM=2, WM=3, WMH=4 (if opt.extropts.WMHC==3)
cat.output.label.native = 0; 
cat.output.label.warped = 0;
cat.output.label.dartel = 0;

% jacobian determinant 0/1 (none/yes)
cat.output.jacobian.warped = 0;

% deformations
% order is [forward inverse]
cat.output.warps        = [0 0];

% experimental maps
%=======================================================================

% partitioning atlas maps (cat12 atlas)
cat.output.atlas.native = 0; 
cat.output.atlas.warped = 0; 
cat.output.atlas.dartel = 0; 

% preprocessing changes map
% this is the map of the MPC QA measure   
cat.output.pc.native = 0;
cat.output.pc.warped = 0;
cat.output.pc.dartel = 0;

% tissue expectation map
cat.output.te.native = 0;
cat.output.te.warped = 0;
cat.output.te.dartel = 0;

% expert options
%=======================================================================

% Subject species: - 'human';'ape_greater';'ape_lesser';'monkey_oldworld';'monkey_newwold' (in development)
cat.extopts.species      = 'human';  

% skull-stripping options
cat.extopts.gcutstr      = 0.5;   % Strengh of skull-stripping:               0 - no gcut; eps - softer and wider; 1 - harder and closer (default = 0.5)
cat.extopts.cleanupstr   = 0.5;   % Strength of the cleanup process:          0 - no cleanup; eps - soft cleanup; 1 - strong cleanup (default = 0.5) 

% segmentation options
cat.extopts.LASstr       = 0.5;   % Strength of the local adaption:           0 - no adaption; eps - lower adaption; 1 - strong adaption (default = 0.5)
cat.extopts.BVCstr       = 0.5;   % Strength of the Blood Vessel Correction:  0 - no correction; eps - low correction; 1 - strong correction (default = 0.5)
cat.extopts.WMHC         = 1;     % Correction of WM hyperintensities:        0 - no (VBM8); 1 - only for Dartel (default); 
                                  %                                           2 - also for segmentation (corred to WM like SPM); 3 - separate class
cat.extopts.WMHCstr      = 0.5;   % Strength of WM hyperintensity correction: 0 - no correction; eps - for lower, 1 for stronger corrections (default = 0.5)
cat.extopts.mrf          = 1;     % MRF weighting:                            0-1 - manuell setting; 1 - auto (default)
cat.extopts.NCstr        = 0.5;   % Strength of the noise correction:         0 - no noise correction; eps - low correction; 1 - strong corrections (default = 0.5)
cat.extopts.sanlm        = 3;     % use SANLM filter: 0 - no SANLM; 1 - SANLM with single-threading; 2 - SANLM with multi-threading (not stable!); 
                                  %                   3 - SANLM with single-threading + ORNLM filter; 4 - SANLM with multi-threading (not stable!) + ORNLM filter;
                                  %                   5 - only ORNLM filter for the final result
cat.extopts.INV          = 1;     % Invert PD/T2 images for standard preprocessing:  0 - no processing, 1 - try invertation (default), 2 - synthesize T1 image

% resolution options:
cat.extopts.restype      = 'best';        % resolution handling: 'native','fixed','best'
cat.extopts.resval       = [1.00 0.10];   % resolution value and its variance for the 'fixed' and 'best' restype

% registration and normalization options 
cat.extopts.vox          = 1.5;                                % voxel size for normalized data (not yet working):  inf - use Tempate values
cat.extopts.bb           = [[-90 -126 -72];[90 90 108]];       % bounding box for normalized data (not yet working): inf - use Tempate values
cat.extopts.darteltpm    = {fullfile(spm('dir'),'toolbox','cat12','templates_1.50mm','Template_1_IXI555_MNI152.nii')};  % Indicate first Dartel template
cat.extopts.cat12atlas   = {fullfile(spm('dir'),'toolbox','cat12','templates_1.50mm','cat12.nii')};                     % VBM atlas with major regions for VBM, SBM & ROIs
cat.extopts.brainmask    = {fullfile(spm('Dir'),'toolbox','FieldMap','brainmask.nii')};                                 % brainmask for affine registration
cat.extopts.T1           = {fullfile(spm('Dir'),'toolbox','FieldMap','T1.nii')};                                        % T1 for affine registration

% surface options
cat.extopts.pbtres       = 0.5;   % resolution for thickness estimation in mm: 1 - normal res (default); 0.5 high res 

% visualisation, print and debugging options
cat.extopts.colormap     = 'BCGWHw'; % {'BCGWHw','BCGWHn'} and matlab colormaps {'jet','gray','bone',...};
cat.extopts.print        = 1;     % Display and print results
cat.extopts.verb         = 2;     % Verbose: 1 - default; 2 - details
cat.extopts.debug        = 0;     % debuging option: 0 - default; 1 - write debugging files 
cat.extopts.ignoreErrors = 1;     % catching preprocessing errors: 1 - catch errors (default); 0 - stop with error 

% QA options -  NOT IMPLEMENTED - just the idea
%cat.extopts.QAcleanup    = 1;     % NOT IMPLEMENTED % move images with questionable or bad quality (see QAcleanupth) to subdirectories
%cat.extopts.QAcleanupth  = [3 5]; % NOT IMPLEMENTED % mark threshold for questionable and bad quality for QAcleanup

cat.extopts.gui           = 1;     % use GUI 

% expert options - ROIs
%=======================================================================
% ROI maps from different sources mapped to VBM-space [IXI555]
%  { filename , refinement , tissue }
%  filename    = ''                                                     - path to the ROI-file
%  refinement  = ['brain','gm','none']                                  - refinement of ROIs in subject space
%  tissue      = {['csf','gm','wm','brain','none','']}                  - tissue classes for volume estimation
cat.extopts.atlas       = { ... 
  fullfile(spm('dir'),'toolbox','cat12','templates_1.50mm','hammers.nii')             'gm'    {'csf','gm','wm'} ; ... % good atlas based on 20 subjects
  fullfile(spm('dir'),'toolbox','cat12','templates_1.50mm','neuromorphometrics.nii')  'gm'    {'csf','gm'};       ... % good atlas based on 35 subjects
 %fullfile(spm('dir'),'toolbox','cat12','templates_1.50mm','ibsr.nii')     'brain' {'gm'}            ; ... % less regions than hammer, 18 subjects, low T1 image quality
 %fullfile(spm('dir'),'toolbox','cat12','templates_1.50mm','anatomy.nii')  'none'  {'gm','wm'}       ; ... % ROIs requires further work >> use Anatomy toolbox
 %fullfile(spm('dir'),'toolbox','cat12','templates_1.50mm','aal.nii')      'gm'    {'gm'}            ; ... % only one subject 
 %fullfile(spm('dir'),'toolbox','cat12','templates_1.50mm','mori.nii')     'brain' {'gm'}            ; ... % only one subject, but with WM regions
  }; 


% IDs of the ROIs in the cat12 atlas map (cat12.nii). Do not change this!
cat.extopts.LAB.NB =  0; % no brain 
cat.extopts.LAB.CT =  1; % cortex
cat.extopts.LAB.CB =  3; % Cerebellum
cat.extopts.LAB.BG =  5; % BasalGanglia 
cat.extopts.LAB.BV =  7; % Blood Vessels
cat.extopts.LAB.TH =  9; % Hypothalamus 
cat.extopts.LAB.ON = 11; % Optical Nerve
cat.extopts.LAB.MB = 13; % MidBrain
cat.extopts.LAB.BS = 13; % BrainStem
cat.extopts.LAB.VT = 15; % Ventricle
cat.extopts.LAB.NV = 17; % no Ventricle
cat.extopts.LAB.HC = 19; % Hippocampus 
cat.extopts.LAB.HD = 21; % Head
cat.extopts.LAB.HI = 23; % WM hyperintensities
