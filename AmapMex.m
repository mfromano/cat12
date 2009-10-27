function [prob, mean] = AmapMex(src, label, nc, niters, sub, pve, init)
%
% Christian Gaser
% $Id$

rev = '$Rev$';

disp('Compiling AmapMex.c')

pth = fileparts(which(mfilename));
p_path = pwd;
cd(pth);
mex -O AmapMex.c Kmeans.c Amap.c MrfPrior.c Pve6.c
cd(p_path);

try 
[prob, mean] = AmapMex(src, label, nc, niters, sub, pve, init);
end

return
