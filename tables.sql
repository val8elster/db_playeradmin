CREATE TABLE players (
    playerId SERIAL PRIMARY KEY,
    name VARCHAR(20) UNIQUE,
    points INT DEFAULT 0
);



CREATE TABLE games (
    gameId SERIAL PRIMARY KEY,
    gameLeaderId INT REFERENCES players(playerId) ON DELETE SET NULL,
    active BIT
);



CREATE TABLE teams (
    teamId SERIAL PRIMARY KEY,
    teamleaderID INT REFERENCES players(playerId) ON DELETE SET NULL,
    gameId INT REFERENCES games(gameId) ON DELETE SET NULL,
    points INT DEFAULT 0,
    teamname VARCHAR(20) UNIQUE,
	active BIT
);



CREATE TABLE sessions (
    sessionId SERIAL PRIMARY KEY,
    maxPinT INT NOT NULL,
    active BIT
);



CREATE TABLE questions (
	questionId SERIAL PRIMARY KEY,
	answer1 VARCHAR(40) NOT NULL,
    answer2 VARCHAR(40) NOT NULL,
	answer3 VARCHAR(40) NOT NULL,
    answer4 VARCHAR(40) NOT NULL,
    rightAnswer INT CHECK (rightAnswer IN (1,2,3,4)),
    qname VARCHAR(50) NOT NULL,
    points INT DEFAULT 10,
    UNIQUE(qname, questionId)
);



CREATE TABLE answered (
	nom SERIAL PRIMARY KEY,
    playerId INT REFERENCES players(playerId) ON DELETE SET NULL,
    questionId INT REFERENCES questions(questionId) ON DELETE SET NULL,
    isCorrect BIT,
	added BIT
);



CREATE TABLE plays (
    teamId INT REFERENCES teams(teamId) ON DELETE SET NULL,
    playerId INT REFERENCES players(playerId) ON DELETE SET NULL,
    gameId INT REFERENCES games(gameId) ON DELETE SET NULL,
    PRIMARY KEY(playerId)
);



CREATE TABLE partOf (
    gameId INT REFERENCES games(gameId) ON DELETE SET NULL,
    sessionId INT REFERENCES sessions(sessionId) ON DELETE SET NULL,
    PRIMARY KEY(sessionId)
);



CREATE TABLE features (
    gameId INT REFERENCES games(gameId) ON DELETE SET NULL,
    questionId INT REFERENCES questions(questionId) ON DELETE SET NULL,
    PRIMARY KEY(gameId, questionId),
    FOREIGN KEY(questionId) REFERENCES questions(questionId)
);



CREATE TABLE statisticsQuestions (
    questionId INT REFERENCES questions(questionId) ON DELETE CASCADE,
    rightAnswers INT DEFAULT 0,
    wrongAnswers INT DEFAULT 0,
	difficulty INT CHECK (difficulty IN (1,2,3,4,5))
);



CREATE TABLE statisticsPlayer (
    placement INT UNIQUE,    
	playerId INT REFERENCES players(playerId) ON DELETE SET NULL,
    points INT DEFAULT 0,
    questionRatio INT DEFAULT 0,
    difficulty1Answered INT DEFAULT 0,
    difficulty2Answered INT DEFAULT 0,
    difficulty3Answered INT DEFAULT 0,
    difficulty4Answered INT DEFAULT 0,
    difficulty5Answered INT DEFAULT 0,
    proficiency INT DEFAULT 0,   
	PRIMARY KEY(playerId)
);