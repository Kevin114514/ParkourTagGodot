Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;

public class ArenaGen {
    const int S = 256;
    static int Cl(double v){ int i=(int)Math.Round(v); if(i<0)i=0; if(i>255)i=255; return i; }

    static double[,] NoiseField(int size,int baseCells,int octaves,double persist,int seed){
        double[,] field=new double[size,size];
        double amp=1.0, total=0.0; int cells=baseCells;
        for(int o=0;o<octaves;o++){
            int c=Math.Max(2,cells);
            Random rnd=new Random(seed*1009+o*97);
            using(Bitmap small=new Bitmap(c,c)){
                for(int yy=0;yy<c;yy++) for(int xx=0;xx<c;xx++){ int v=rnd.Next(0,256); small.SetPixel(xx,yy,Color.FromArgb(v,v,v)); }
                using(Bitmap big=new Bitmap(size,size))
                using(Graphics g=Graphics.FromImage(big)){
                    g.InterpolationMode=InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode=PixelOffsetMode.HighQuality;
                    g.DrawImage(small,new Rectangle(0,0,size,size),new Rectangle(0,0,c,c),GraphicsUnit.Pixel);
                    for(int y=0;y<size;y++) for(int x=0;x<size;x++){ field[y,x]+=amp*(big.GetPixel(x,y).R/255.0); }
                }
            }
            total+=amp; amp*=persist; cells*=2;
        }
        double inv=1.0/total;
        for(int y=0;y<size;y++) for(int x=0;x<size;x++) field[y,x]*=inv;
        return field;
    }

    // 混凝土：均值偏亮的细颗粒 + 稀疏暗斑，无方向性
    public static void Concrete(string path,int seed){
        double[,] grain=NoiseField(S,48,4,0.55,seed+1);
        double[,] speck=NoiseField(S,120,2,0.5,seed+7);
        double[,] blot=NoiseField(S,10,3,0.55,seed+3);
        using(Bitmap img=new Bitmap(S,S)){
            for(int y=0;y<S;y++) for(int x=0;x<S;x++){
                double v=236.0;
                v+=(grain[y,x]-0.5)*20.0;      // 细颗粒
                v+=(blot[y,x]-0.5)*10.0;        // 大块明暗
                double s=speck[y,x];
                if(s<0.12) v-=(0.12-s)/0.12*40.0; // 稀疏暗孔
                img.SetPixel(x,y,Color.FromArgb(Cl(v),Cl(v),Cl(v)));
            }
            img.Save(path,System.Drawing.Imaging.ImageFormat.Png);
        }
    }

    // 木纹：沿 Y 轴的板材纹理（长条纹 + 木纹起伏），灰度高明度
    public static void Wood(string path,int seed){
        double[,] fib=NoiseField(S,80,3,0.5,seed+1);    // 细木纤维
        double[,] wob=NoiseField(S,6,2,0.5,seed+5);     // 纹理起伏
        int planks=5; double pw=(double)S/planks;
        Random rnd=new Random(seed);
        double[] tint=new double[planks]; for(int i=0;i<planks;i++) tint[i]=rnd.NextDouble()*10-5;
        using(Bitmap img=new Bitmap(S,S)){
            for(int y=0;y<S;y++) for(int x=0;x<S;x++){
                int pi=(int)(x/pw);
                double v=234.0+tint[pi];
                // 木纹条纹：随 x 缓变、随 y 拉长
                double grain=Math.Sin((x*0.5 + wob[y,x]*40.0 + fib[y,x]*8.0))*0.5+0.5;
                v-=grain*16.0;
                v+=(fib[y,x]-0.5)*10.0;
                // 板缝
                double edge=Math.Min(x-pi*pw,(pi+1)*pw-x)/pw;
                if(edge<0.03) v-=(0.03-edge)/0.03*55.0;
                img.SetPixel(x,y,Color.FromArgb(Cl(v),Cl(v),Cl(v)));
            }
            img.Save(path,System.Drawing.Imaging.ImageFormat.Png);
        }
    }

    // 金属：横向拉丝，均值高明度
    public static void Metal(string path,int seed){
        double[,] brush=NoiseField(S,220,1,0.5,seed+1); // 横向高频（拉丝）
        double[,] wide=NoiseField(S,8,2,0.5,seed+4);
        using(Bitmap img=new Bitmap(S,S)){
            for(int y=0;y<S;y++) for(int x=0;x<S;x++){
                double v=240.0;
                v+=(brush[y,x]-0.5)*14.0;
                v+=(wide[y,x]-0.5)*8.0;
                img.SetPixel(x,y,Color.FromArgb(Cl(v),Cl(v),Cl(v)));
            }
            img.Save(path,System.Drawing.Imaging.ImageFormat.Png);
        }
    }
}
"@ -ReferencedAssemblies System.Drawing

$dir = 'C:\Users\p_zilinqu\CodeBuddy\Parkour Tag\maps\textures\arena'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[ArenaGen]::Concrete((Join-Path $dir 'concrete.png'), 101)
[ArenaGen]::Wood((Join-Path $dir 'wood.png'), 202)
[ArenaGen]::Metal((Join-Path $dir 'metal.png'), 303)
Write-Output 'arena textures generated'
