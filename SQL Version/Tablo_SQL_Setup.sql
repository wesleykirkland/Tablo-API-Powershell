/****** Object:  Database [Tablo]    Script Date: 7/3/2016 1:37:43 PM ******/
CREATE DATABASE [Tablo]
 CONTAINMENT = NONE
 ON  PRIMARY 
( NAME = N'Tablo', FILENAME = N'D:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\DATA\Tablo.mdf' , SIZE = 10240KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB )
 LOG ON 
( NAME = N'Tablo_log', FILENAME = N'D:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\DATA\Tablo_log.ldf' , SIZE = 1280KB , MAXSIZE = 2048GB , FILEGROWTH = 10%)
GO

IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
begin
EXEC [Tablo].[dbo].[sp_fulltext_database] @action = 'enable'
end
GO

ALTER DATABASE [Tablo] SET ANSI_NULL_DEFAULT OFF 
GO

ALTER DATABASE [Tablo] SET ANSI_NULLS OFF 
GO

ALTER DATABASE [Tablo] SET ANSI_PADDING OFF 
GO

ALTER DATABASE [Tablo] SET ANSI_WARNINGS OFF 
GO

ALTER DATABASE [Tablo] SET ARITHABORT OFF 
GO

ALTER DATABASE [Tablo] SET AUTO_CLOSE OFF 
GO

ALTER DATABASE [Tablo] SET AUTO_SHRINK OFF 
GO

ALTER DATABASE [Tablo] SET AUTO_UPDATE_STATISTICS ON 
GO

ALTER DATABASE [Tablo] SET CURSOR_CLOSE_ON_COMMIT OFF 
GO

ALTER DATABASE [Tablo] SET CURSOR_DEFAULT  GLOBAL 
GO

ALTER DATABASE [Tablo] SET CONCAT_NULL_YIELDS_NULL OFF 
GO

ALTER DATABASE [Tablo] SET NUMERIC_ROUNDABORT OFF 
GO

ALTER DATABASE [Tablo] SET QUOTED_IDENTIFIER OFF 
GO

ALTER DATABASE [Tablo] SET RECURSIVE_TRIGGERS OFF 
GO

ALTER DATABASE [Tablo] SET  DISABLE_BROKER 
GO

ALTER DATABASE [Tablo] SET AUTO_UPDATE_STATISTICS_ASYNC OFF 
GO

ALTER DATABASE [Tablo] SET DATE_CORRELATION_OPTIMIZATION OFF 
GO

ALTER DATABASE [Tablo] SET TRUSTWORTHY OFF 
GO

ALTER DATABASE [Tablo] SET ALLOW_SNAPSHOT_ISOLATION OFF 
GO

ALTER DATABASE [Tablo] SET PARAMETERIZATION SIMPLE 
GO

ALTER DATABASE [Tablo] SET READ_COMMITTED_SNAPSHOT OFF 
GO

ALTER DATABASE [Tablo] SET HONOR_BROKER_PRIORITY OFF 
GO

ALTER DATABASE [Tablo] SET RECOVERY SIMPLE 
GO

ALTER DATABASE [Tablo] SET  MULTI_USER 
GO

ALTER DATABASE [Tablo] SET PAGE_VERIFY CHECKSUM  
GO

ALTER DATABASE [Tablo] SET DB_CHAINING OFF 
GO

ALTER DATABASE [Tablo] SET FILESTREAM( NON_TRANSACTED_ACCESS = OFF ) 
GO

ALTER DATABASE [Tablo] SET TARGET_RECOVERY_TIME = 0 SECONDS 
GO

ALTER DATABASE [Tablo] SET DELAYED_DURABILITY = DISABLED 
GO

ALTER DATABASE [Tablo] SET  READ_WRITE 
GO


USE [Tablo]
GO

/****** Object:  Table [dbo].[Post_Processing_Exceptions]    Script Date: 7/3/2016 1:39:31 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[Post_Processing_Exceptions](
	[PK] [int] IDENTITY(1,1) NOT NULL,
	[PostProcessException] [varchar](100) NOT NULL,
 CONSTRAINT [PK_Post_Processing_Exceptions] PRIMARY KEY CLUSTERED 
(
	[PK] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

/****** Object:  Table [dbo].[TV_Shows]    Script Date: 7/3/2016 1:39:43 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[TV_Shows](
	[Show] [varchar](100) NOT NULL,
 CONSTRAINT [PK_TV_Shows] PRIMARY KEY CLUSTERED 
(
	[Show] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO


/****** Object:  Table [dbo].[TV_Recordings]    Script Date: 7/3/2016 1:39:37 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[TV_Recordings](
	[RecID] [numeric](16, 0) NOT NULL,
	[FileName] [varchar](255) NOT NULL,
	[EpisodeName] [varchar](255) NULL,
	[Show] [varchar](100) NOT NULL,
	[EpisodeSeason] [numeric](4, 0) NULL,
	[EpisodeNumber] [numeric](4, 0) NULL,
	[AirDate] [date] NOT NULL,
	[PostProcessDate] [datetime] NOT NULL,
	[Description] [text] NULL,
	[Media] [varchar](10) NOT NULL,
	[Processed] [bit] NULL,
	[ProcessedByMCEBuddy] [bit] NULL,
 CONSTRAINT [PK_TV_Recordings] PRIMARY KEY CLUSTERED 
(
	[RecID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

ALTER TABLE [dbo].[TV_Recordings] ADD  CONSTRAINT [DF_TV_Recordings_Media]  DEFAULT (N'TV') FOR [Media]
GO

ALTER TABLE [dbo].[TV_Recordings]  WITH CHECK ADD  CONSTRAINT [FK_TV_Recordings_TV_Shows] FOREIGN KEY([Show])
REFERENCES [dbo].[TV_Shows] ([Show])
ON UPDATE CASCADE
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[TV_Recordings] CHECK CONSTRAINT [FK_TV_Recordings_TV_Shows]
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'TV Show Key' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'TV_Recordings', @level2type=N'CONSTRAINT',@level2name=N'FK_TV_Recordings_TV_Shows'
GO


/****** Object:  Table [dbo].[Air_Date_Exceptions]    Script Date: 7/3/2016 1:39:25 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[Air_Date_Exceptions](
	[PK] [int] IDENTITY(1,1) NOT NULL,
	[AirDateException] [nchar](100) NOT NULL,
 CONSTRAINT [PK_Air_Date_Exceptions] PRIMARY KEY CLUSTERED 
(
	[PK] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO


/****** Object:  Table [dbo].[MOVIE_Recordings]    Script Date: 7/3/2016 1:39:13 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[MOVIE_Recordings](
	[RecID] [numeric](16, 0) NOT NULL,
	[FileName] [varchar](255) NOT NULL,
	[AirDate] [date] NULL,
	[PostProcessDate] [datetime] NOT NULL,
	[Media] [varchar](10) NOT NULL,
	[Processed] [bit] NULL,
	[ProcessedByMCEBuddy] [bit] NULL,
 CONSTRAINT [PK_MOVIE_Recordings] PRIMARY KEY CLUSTERED 
(
	[RecID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [dbo].[MOVIE_Recordings] ADD  CONSTRAINT [DF_MOVIE_Recordings_Media]  DEFAULT (N'MOVIE') FOR [Media]
GO

/****** Object:  Table [dbo].[TV_Recordings_Warnings]    Script Date: 11/18/2016 9:32:15 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dbo].[TV_Recordings_Warnings](
	[RecID] [numeric](16, 0) NOT NULL,
	[Show] [varchar](100) NOT NULL,
	[EpisodeSeason] [numeric](4, 0) NULL,
	[EpisodeNumber] [numeric](4, 0) NULL,
	[AirDate] [nchar](10) NOT NULL
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

ALTER TABLE [dbo].[TV_Recordings_Warnings]  WITH CHECK ADD  CONSTRAINT [FK_TV_Recordings_Warnings_TV_Shows] FOREIGN KEY([Show])
REFERENCES [dbo].[TV_Shows] ([Show])
GO

ALTER TABLE [dbo].[TV_Recordings_Warnings] CHECK CONSTRAINT [FK_TV_Recordings_Warnings_TV_Shows]
GO


