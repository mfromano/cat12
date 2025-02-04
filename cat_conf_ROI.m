function [ROI,sROI,ROIsum] = cat_conf_ROI(expert)
%_______________________________________________________________________
% wrapper for calling CAT ROI options
% ______________________________________________________________________
%
% Christian Gaser, Robert Dahnke
% Structural Brain Mapping Group (https://neuro-jena.github.io)
% Departments of Neurology and Psychiatry
% Jena University Hospital
% ______________________________________________________________________
% $Id$


if nargin == 0
  try
    expert = cat_get_defaults('extopts.expertgui');
  catch %#ok<CTCH>
    expert = 0; 
  end
end

noROI        = cfg_branch;
noROI.tag    = 'noROI';
noROI.name   = 'No ROI processing';
noROI.help   = {'No ROI processing'};

exatlas  = cat_get_defaults('extopts.atlas'); 
matlas = {}; mai = 1; atlaslist = {}; 
for ai = 1:size(exatlas,1)
  if exatlas{ai,2}<=expert && exist(exatlas{ai,1},'file')
    [pp,ff]  = spm_fileparts(exatlas{ai,1}); 

    % if output.atlases.ff does not exist then set it by the default file value
    if isempty(cat_get_defaults(['output.atlases.' ff]))
      cat_get_defaults(['output.atlases.' ff], exatlas{ai,4})
    end
    atlaslist{end+1,1} = ff; 

    license = {'' ' (no commercial use)' ' (free academic use)'}; 
    if size(exatlas,2)>4
      lic = exatlas{ai,5}; 
    else
      switch ff
        case 'hammers', lic = 2; 
        case 'lpba40' , lic = 1; 
        case 'suit',    lic = 1; 
        otherwise,      lic = 0; 
      end
    end
    
    matlas{mai}        = cfg_menu;
    matlas{mai}.tag    = ff;
    matlas{mai}.name   = [ff license{lic+1}]; 
    matlas{mai}.labels = {'No','Yes'};
    matlas{mai}.values = {0 1};
    matlas{mai}.def    = eval(sprintf('@(val) cat_get_defaults(''output.atlases.%s'', val{:});',ff)); 
    txtfile = fullfile(pp,[ff '.txt']);
    if exist(txtfile,'file')
      fid = fopen(txtfile,'r');
      txt = textscan(fid,'%s','delimiter','\n');
      fclose(fid);
      matlas{mai}.help   = [{ 
        'Processing flag of this atlas map.'
        ''
        }
        txt{1}];
    else
      matlas{mai}.help   = {
        'Processing flag of this atlas map.'
        ''
        ['No atlas readme text file "' txtfile '"!']
      };
    end
    mai = mai+1; 
  else
    [pp,ff]  = spm_fileparts(exatlas{ai,1}); 
    
    if ~isempty(cat_get_defaults(['output.atlases.' ff]))
      cat_get_defaults(['output.atlases.' ff],'rmfield');
    end
  end
end

ownatlas              = cfg_files;
ownatlas.tag          = 'ownatlas';
ownatlas.name         = 'own atlas maps';
ownatlas.help         = { 
  sprintf([
    'Select images that should be used as atlas maps.  ' ...
    'The maps should only contain positive integers for regions of interest.  ' ...
    'You can use a CSV-file with the same name as the atlas to define region ' ...
    'names similar to the CSV-files of other atlas files in "%s".  ' ...
    'The CSV-file should have an header line containing the number of the ROI "ROIid", ' ...
    'the abbreviation of the ROI "ROIabbr" (using leading l/r/b to indicate the hemisphere) ' ...
    'and the full name of the ROI "ROIname".  ' ...
    'The GM, WM, and CSF values will be extracted for all regions. '], ...
    cat_get_defaults('extopts.pth_templates') ); 
  ''};
ownatlas.filter       = 'image';
ownatlas.ufilter      = '.*';
ownatlas.val{1}       = {''};
ownatlas.dir          = cat_get_defaults('extopts.pth_templates');
ownatlas.num          = [0 Inf];

atlases          = cfg_branch;
atlases.tag      = 'atlases';
atlases.name     = 'Atlases';
atlases.val      = [matlas,{ownatlas}];
atlases.help     = {'Writing options of ROI atlas maps.'
''
};


ROI        = cfg_choice;
ROI.tag    = 'ROImenu';
ROI.name   = 'Process Volume ROIs';
if cat_get_defaults('output.ROI')>0
  ROI.val  = {atlases};
else
  ROI.val  = {noROI};
end
ROI.values = {noROI atlases};
ROI.help   = {
'Export of ROI data of volume to a xml-files. For further information see atlas specific text files in'
['  "' cat_get_defaults('extopts.pth_templates') '" CAT12 subdir. ']
''
'For thickness estimation the projection-based thickness (PBT) [Dahnke:2012] is used that average cortical thickness for each GM voxel. '
''
'There are different atlas maps available: '
}; 

%%
mai = 1; 
for ali=1:numel(atlaslist)
  if any(~cellfun('isempty',strfind(atlaslist(ali),'hammers')))
    ROI.help = [ROI.help; strrep({
        '(MAI) Hammers (68 CSF/GM/[WM] ROIs of 20 subjects, 2003):'
        '    Alexander Hammers brain atlas from the Euripides project (www.brain-development.org).'
        '    Hammers et al. Three-dimensional maximum probability atlas of the human brain, with particular reference to the temporal lobe. Hum Brain Mapp 2003, 19: 224-247.'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'neuromorphometrics')))
    ROI.help = [ROI.help; strrep({
        '(MAI) Neuromorphometrics (142 GM ROIs of 15 subjects, 2012):'
        '    Maximum probability tissue labels derived from the MICCAI 2012 Grand Challenge and Workshop on Multi-Atlas Labeling'
        '    https://masi.vuse.vanderbilt.edu/workshop2012/index.php/Challenge_Details'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'lpba40')))
    ROI.help = [ROI.help; strrep({
        '(MAI) LPBA40 (56 GM ROIs of 40 subjects, 2008):'
        '    The LONI Probabilistic Brain Atlas (LPBA40) is a series of maps of brain anatomical regions. These maps were estimated from a set of whole-head MRI of 40 human volunteers. Each MRI was manually delineated to identify a set of 56 structures in the brain, most of which are within the cortex. These delineations were then transformed into a common atlas space to obtian a set of coregistered anatomical labels. The original MRI data were also transformed into the atlas space. '
        '    Shattuck et al. 2008. Construction of a 3D Probabilistic Atlas of Human Cortical Structures, NeuroImage 39 (3): 1064-1070. DOI:	10.1016/j.neuroimage.2007.09.031'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'cobra')))
    ROI.help = [ROI.help; strrep({
        '(MAI) COBRA (1 GM/WM ROI in amgdala, 2 combined GM/WM ROIs in hippocampus and 13 GM/WM ROIs in cerebellum of 5 subjects):'
        '    The Cobra atlas is build from 3 atlases that are provided by the Computational Brain Anatomy Laboratory at the Douglas Institute (CoBra Lab). The 3 atlases are based on high-resolution (0.3mm isotropic voxel size) images of the amygdala, hippocampus and the cerebellum. Some of the hippocampus subfields were merged because of their small size (CA1/CA2/CA3/stratum radiatum/subiculum/stratum lacunosum/stratum moleculare). Please note that the original labels were changed in order to allow a combined atlas. '
        '    Entis JJ, Doerga P, Barrett LF, Dickerson BC. A reliable protocol for the manual segmentation of the human amygdala and its subregions using ultra-high resolution MRI. Neuroimage. 2012;60(2):1226-35.'
        '    Winterburn JL, Pruessner JC, Chavez S, et al. A novel in vivo atlas of human hippocampal subfields using high-resolution 3 T magnetic resonance imaging.  Neuroimage. 2013;74:254-65.'
        '    Park, M.T., Pipitone, J., Baer, L., Winterburn, J.L., Shah, Y., Chavez, S., Schira, M.M., Lobaugh, N.J., Lerch, J.P., Voineskos, A.N., Chakravarty, M.M. Derivation of high-resolution MRI atlases of the human cerebellum at 3T and segmentation using multiple automatically generated templates. Neuroimage. 2014; 95: 217-31.'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'ibsr')))
    ROI.help = [ROI.help; strrep({
        '(MAI) IBSR (32 CSF/GM ROIs of 18 subjects, 2004):'
        '    See IBSR terms "http://www.nitrc.org/projects/ibsr"'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'aal3')))
    ROI.help = [ROI.help; strrep({
        '(MAI) AAL3 (170 GM ROIs of 1 subject, 2020):'
        '    Tzourio-Mazoyer et al., Automated anatomical labelling of activations in spm using a macroscopic anatomical parcellation of the MNI MRI single subject brain. Neuroimage 2002, 15: 273-289.'
        '    Rolls et al., Automated anatomical labelling atlas 3. Neuroimage 2020; 206:116189.'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'mori')))
    ROI.help = [ROI.help; strrep({
        '(MAI) MORI (128 GM/WM ROIs of 1 subject, 2009):'
        '    Oishi et al. Atlas-based whole brain white matter analysis using large deformation diffeomorphic metric mapping: application to normal elderly and Alzheimer''s disease participants. 2009'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'anatomy3')))
    ROI.help = [ROI.help; strrep({
        '(MAI) Anatomy (93 GM/WM ROIs in 10 post-mortem subjects, 2014):'
        '    Eickhoff SB, Stephan KE, Mohlberg H, Grefkes C, Fink GR, Amunts K, Zilles K. A new SPM toolbox for combining probabilistic cytoarchitectonic maps and functional imaging data. NeuroImage 25(4), 1325-1335, 2005'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'julichbrain')))
    ROI.help = [ROI.help; strrep({
        '(MAI) Whole-brain parcellation of the Julich-Brain Cytoarchitectonic Atlas (v2.0):'
        '    Amunts K, Mohlberg H, Bludau S, Zilles K (2020). Julich-Brain – A 3D probabilistic atlas of human brains cytoarchitecture. Science 369, 988-99'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'thalamus')))
    ROI.help = [ROI.help; strrep({
        '(MAI) Atlas of human thalamic nuclei (based on DTI from 70 subjects with 14 regions):'
        '    Najdenovska E, Alemán-Gómez Y, Battistella G, Descoteaux M, Hagmann P, Jacquemont S, Maeder P, Thiran JP, Fornari E, Bach Cuadra M. In-vivo probabilistic atlas of human thalamic nuclei based on diffusion- weighted magnetic resonance imaging. Sci Data. 2018 Nov 27;5:180270.'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'thalamic_nuclei')))
    ROI.help = [ROI.help; strrep({
        '(MAI) Atlas of human thalamic nuclei (based on hi-res T2 from 9 subjects with 22 regions):'
        '    Saranathan M, Iglehart C, Monti M, Tourdias T, Rutt B. In vivo high-resolution structural MRI-based atlas of human thalamic nuclei. Sci Data. 2021 Oct 28;8(1):275.'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'suit')))
    ROI.help = [ROI.help; strrep({
        '(MAI) SUIT Atlas of the human cerebellum:'
        '    Diedrichsen J., Balster J.H., Flavell J., Cussans E., Ramnani N. (2009). A probabilistic MR atlas of the human cerebellum. Neuroimage; 46(1), 39-46.'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
  if any(~cellfun('isempty',strfind(atlaslist(ali),'Schaefer2018_200Parcels_17Networks_order')))
    ROI.help = [ROI.help; strrep({
        '(MAI) Local-Global Intrinsic Functional Connectivity Parcellation by Schaefer et al.:'
        'These atlases are available for different numbers of parcellations (100, 200, 400, 600)'
        'and are based on resting state data from 1489 subjects.'
        'https://github.com/ThomasYeoLab/CBIG/tree/master/stable_projects/brain_parcellation/Schaefer2018_LocalGlobal'
        ''},'MAI',num2str(mai,'%d'))]; mai = mai+1; 
  end
end
 


%% ------------------------------------------------------------------------
% Surface Atlases
% RD 20190416
%------------------------------------------------------------------------

nosROI        = cfg_branch;
nosROI.tag    = 'noROI';
nosROI.name   = 'No surface ROI processing';
nosROI.help   = {'No surface ROI processing'};

exatlas  = cat_get_defaults('extopts.satlas'); 
matlas = {}; mai = 1; atlaslist = {}; 
for ai = 1:size(exatlas,1)
  if exatlas{ai,3}<=expert && ~isempty(exatlas{ai,2})
    [pp,ff]  = spm_fileparts( exatlas{ai,2} ); 
    name = exatlas{ai,1}; 

    % if output.atlases.ff does not exist then set it by the default file value
    if isempty(cat_get_defaults(['output.satlases.' name]))
      cat_get_defaults(['output.satlases.' name], exatlas{ai,4})
    end
    atlaslist{end+1,1} = name; 

    if cat_get_defaults('extopts.expertgui') 
      if strcmp(spm_str_manip(pp,'t'),'atlases_surfaces_32k')
        addname = ' (32k)';
      elseif strcmp(spm_str_manip(pp,'t'),'atlases_surfaces')
        addname = ' (164k)';
      else
        addname = '';
      end
    else
      addname = '';
    end
    
    matlas{mai}        = cfg_menu;
    matlas{mai}.tag    = name;
    matlas{mai}.name   = [name addname]; 
    matlas{mai}.labels = {'No','Yes'};
    matlas{mai}.values = {0 1};
    matlas{mai}.def    = eval(sprintf('@(val) cat_get_defaults(''output.satlases.%s'', val{:});',name)); 
    
    txtfile = fullfile(pp,[name '.txt']);
    if exist(txtfile,'file')
      fid = fopen(txtfile,'r');
      txt = textscan(fid,'%s','delimiter','\n');
      fclose(fid);
      matlas{mai}.help   = [{ 
        'Processing flag of this atlas map.'
        ''
        }
        txt{1}];
    else
      matlas{mai}.help   = {
        'Processing flag of this atlas map.'
        ''
        ['No atlas readme text file "' txtfile '"!']
      };
    end
    mai = mai+1; 
  else
    name = exatlas{ai,1}; 
    
    if ~isempty(cat_get_defaults(['output.satlases.' name]))
      cat_get_defaults(['output.satlases.' name],'rmfield');
    end
  end
end

ownsatlas          = ownatlas;
ownsatlas.filter   = '';
ownsatlas.ufilter  = '.*'; 
ownsatlas.help     = { 
  'Select FreeSurfer surface annotation files (*.annot), FreeSurfer CURV-files, or GIFTI surfaces with positve integer with 32k or 164k faces. ';
  ''};

satlases          = cfg_branch;
satlases.tag      = 'satlases';
satlases.name     = 'Surface atlases';
satlases.val      = [matlas,{ownatlas}];
satlases.help     = {'Writing options for surface ROI atlas maps.'
''
};


sROI        = cfg_choice;
sROI.tag    = 'sROImenu';
sROI.name   = 'Process Surface ROIs';
if cat_get_defaults('output.surface')>0 && cat_get_defaults('output.ROI')>0
  sROI.val  = {satlases};
else
  sROI.val  = {nosROI};
end
sROI.values = {nosROI satlases};
sROI.help   = {
'Export of ROI data of volume to a xml-files. '
['For further information see atlas specific text files in "' cat_get_defaults('extopts.pth_templates') '" CAT12 subdir. ']
''
'For thickness estimation the projection-based thickness (PBT) [Dahnke:2012] is used that averages cortical thickness for each GM voxel. '
''
'There are different atlas maps available: '
}; 

%-------------------------------------------------------------
% summarize in ROI 
atlases.help    = {'ROI atlas maps. In order to obtain more atlases you have to switch to expert mode.'};

field           = cfg_files;
field.tag       = 'field';
field.name      = 'Deformation Fields';
field.filter    = 'image';
field.ufilter   = '^y_.*\.nii$';
field.num       = [1 Inf];
field.help      = {
  'Select deformation fields for all subjects.'
  'Use the "y_*.nii" to project data from subject to template space, and the "iy_*.nii" to map data from template to individual space.'
  'Both deformation maps can be created in the CAT preprocessing by setting the "Deformation Field" flag to forward or inverse.' 
};

field1          = cfg_files;
field1.tag      = 'field1';
field1.name     = 'Deformation Field';
field1.filter   = 'image';
field1.ufilter  = '^y_.*\.nii$';
field1.num      = [1 1];
field1.help     = {
  'Select the deformation field of one subject.'
  'Use the "y_*.nii" to project data from subject to template space, and the "iy_*.nii" to map data from template to individual space.'
  'Both deformation maps can be created in the CAT preprocessing by setting the "Deformation Field" flag to forward or inverse.' 
};

images1         = cfg_files;
images1.tag     = 'images';
images1.name    = 'Images';
images1.help    = {
  'Select co-registered files for ROI estimation. It is important that this image is in the same space and co-registered to  the T1-weighted image. Note that there should be the same number of images as there are '
  'deformation fields, such that each flow field relates to one image. The images can be also given as 4D data (e.g. rsfMRI data).'
};
images1.filter  = 'image';
images1.ufilter = '.*';
images1.num     = [1 Inf];

images          = cfg_repeat;
images.tag      = 'images';
images.name     = 'Images';
images.help     = {'ROI estimation can be done for multiple images of one subject. At this point, you are choosing how many images for each flow field exist.'};
images.values   = {images1 };
images.num      = [1 Inf];

cfun            = cfg_entry;
cfun.tag        = 'cfun';
cfun.name       = 'Customized function';
cfun.strtype    = 's';
cfun.num        = [0 Inf];
cfun.val        = {'@median'};
cfun.help       = {
  'Here, you can define your own function to summarize data as function handle. This also allows to use external functions.'
  'Examples: '
  'Calculate median:'
  '@median'
  ''
  'Calculate absolute amplitude between 10-90% percentile:'
  '@(x) abs(diff(spm_percentile(x,[10 90])))'
  ''
  'Get mean inbetween 10-90% percentile'
  '@(x) mean(x>spm_percentile(x,10) & x<spm_percentile(x,90)'
  ''
};

fun             = cfg_menu;
fun.name        = 'Predefined functions';
fun.tag         = 'fun';
fun.labels      = {'Volume (in ml)','Mean','Standard Deviation'};
fun.values      = {'volume','@mean','@std'};
fun.val         = {'@mean'};
fun.help        = {'Select predfined function to summarize data within a ROI.'};

fhandle         = cfg_choice;
fhandle.tag     = 'fhandle';
fhandle.name    = 'Function to summarize?';
fhandle.val     = {fun};
fhandle.values  = {fun cfun};
fhandle.help    = {'Select either a predefined function or define your own function handle to summarize data within a ROI.'};

% update help text
images1.help    = {'Select co-registered files for ROI estimation for this subject. The images can be also given as 4D data (e.g. rsfMRI data).'};

ManyImages      = cfg_exbranch;
ManyImages.tag  = 'ManyImages';
ManyImages.name = 'Summarise data for many images of one subject';
ManyImages.val  = {field1,images1,atlases,fhandle};
ManyImages.help = {'Summarise data within a region of interest (ROI) of multiple images for one subject.'};

ManySubj        = cfg_exbranch;
ManySubj.tag    = 'ManySubj';
ManySubj.name   = 'Summarise data for many subjects';
ManySubj.val    = {field,images,atlases,fhandle};
ManySubj.help   = {'Summarise data within a region of interest (ROI) for many subjects with one or more images each.'};

Method          = cfg_choice;
Method.tag      = 'Method';
Method.name     = 'Select method?';
Method.values   = {ManyImages ManySubj};
Method.val      = {ManyImages};
Method.help     = {'Select method.'};

ROIsum          = cfg_exbranch;
ROIsum.tag      = 'ROIsum';
ROIsum.name     = 'Summarise 3D/4D volume data within a ROI';
ROIsum.val      = {Method};
ROIsum.prog     = @cat_vol_ROI_summarize;
ROIsum.help     = {
  'This is an utility to summarise co-registered volume data within a region of interest (ROI). '
  'This tool can be used in order to estimate ROI information for other modalities (i.e. DTI, (rs)fMRI) which can be also defined as 4D data.'
  'In contrast to the tool "Estimate mean/volume inside ROI", any atlas can be used here even after preprocessing and several summarize functions are available.'
};

