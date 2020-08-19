import React, { useState, useEffect, useCallback, useRef } from 'react';
import './App.css';
import 'fontsource-roboto';
import Button from '@material-ui/core/Button';
import Grid from '@material-ui/core/Grid';
import TextField from '@material-ui/core/TextField';
import Link from '@material-ui/core/Link';
import CircularProgress from '@material-ui/core/CircularProgress';
import Table from '@material-ui/core/Table';
import TableBody from '@material-ui/core/TableBody';
import TableCell from '@material-ui/core/TableCell';
import TableRow from '@material-ui/core/TableRow';

import { makeStyles } from '@material-ui/core/styles';


const API_BASE = 'https://libc.rip/api';

const api = async (path, data) => {
  let resp = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    mode: 'cors',
    cache: 'no-cache',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(data),
  });
  return await resp.json();
};

const useStyles = makeStyles((theme) => ({
  root: {
    '& .MuiTextField-root': {
      margin: theme.spacing(1),
    },
    '& .MuiButton-root': {
      margin: theme.spacing(1),
    },
    '& .remove': {
      marginTop: '1.2rem',
      height: '2rem',
    },
    '& .findbutton': {
      marginTop: '1.2rem',
    },
  },
  table: {
    marginTop: '1rem',
    marginBottom: '1rem',
  }
}));


function SearchRow({ onChange = () => {}, onRemove = () => {} }) {
  const [symbol, setSymbol] = useState("");
  const [address, setAddress] = useState("");
  const [addressValid, setAddressValid] = useState(true);

  const onSymbolChange = useCallback((evt) => {
    setSymbol(evt.target.value);
  }, []);

  const onAddressChange = useCallback((evt) => {
    setAddress(evt.target.value);
  }, []);

  useEffect(() => {
    const valid = !!address.match(/^(0x)?[0-9a-fA-F]*$/);
    setAddressValid(valid);
    onChange({valid, symbol, address});
  }, [address, symbol, onChange]);

  return (
    <div>
      <TextField label="Symbol name" value={symbol} onChange={onSymbolChange} />
      <TextField label="Address" error={!addressValid} value={address} onChange={onAddressChange} />
      <Button className="remove" variant="contained" color="secondary" onClick={onRemove}>
        Remove
      </Button>
    </div>
  );
}

function SearchForm({ onSearch = () => {} }) {
  const classes = useStyles();
  const [nextId, setNextId] = useState(0);
  const [rows, setRows] = useState([]);
  const [states, setStates] = useState({});
  const onRemoveRef = useRef();
  const onChangeRef = useRef();

  const makeRow = (id) => {
    return (
      <SearchRow key={id}
        onRemove={() => onRemoveRef.current(id)}
        onChange={(obj) => onChangeRef.current(id, obj)} />);
  };

  const isEmpty = useCallback((i) => {
    let state = states[rows[i].key];
    return !state || (!state.symbol && !state.address);
  }, [rows, states]);

  // Add new empty rows automatically
  useEffect(() => {
    let need = true;
    for (let i = 0; i < rows.length; ++i) {
      if (isEmpty(i)) {
        need = false;
        break;
      }
    }

    if (need) {
      setRows(rows => rows.concat([makeRow('' + nextId)]));
      setNextId(id => id + 1);
    }
  }, [rows, states, nextId, isEmpty]);

  // Remove superfluous rows at the end
  useEffect(() => {
    let i = rows.length - 1;
    while (i >= 1 && isEmpty(i) && isEmpty(i-1)) {
      --i;
    }
    if (i < rows.length - 1) {
      setRows(rows => rows.slice(0, i+1));
    }
  }, [rows, states, nextId, isEmpty]);

  const onRemove = useCallback((id) => {
    for (let i = 0; i < rows.length; ++i) {
      if (rows[i].key === id) {
        setRows(rows.slice(0, i).concat(rows.slice(i+1)));
        return;
      }
    }
  }, [rows]);

  const onChange = useCallback((id, obj) => {
    setStates({...states, [id]: obj});
  }, [states]);

  onChangeRef.current = onChange;
  onRemoveRef.current = onRemove;

  const onSubmit = useCallback(() => {
    let symbols = {};
    for (let row of rows) {
      let state = states[row.key];
      if (state && state.valid && state.address && state.symbol) {
        symbols[state.symbol] = state.address;
      }
    }
    onSearch({"symbols": symbols});
  }, [rows, states, onSearch]);

  const isValid = useCallback(() => {
    let cnt = 0;
    for (let row of rows) {
      let state = states[row.key];
      if (!state)
        continue;
      if (!state.valid)
        return false;
      if (state.address && state.symbol)
        cnt++;
    }
    return cnt > 0;
  }, [rows, states]);

  return (
    <form className={classes.root}>
      {rows}

      <div>
        <Button
          disabled={!isValid()}
          variant="contained"
          className="findbutton"
          color="primary"
          onClick={onSubmit}>
          Find
        </Button>
      </div>
    </form>
  );
}

function Result({ id, buildid, md5, symbols, download_url }) {
  const classes = useStyles();
  const [open, setOpen] = useState(false);

  const onToggle = useCallback((evt) => {
    evt.preventDefault();
    setOpen(!open);
  }, [open]);

  let symbolRows = Object.entries(symbols).map(([k, v]) => (
    <TableRow key={k}>
      <TableCell><code>{k}</code></TableCell>
      <TableCell><code>{v}</code></TableCell>
    </TableRow>
  ));

  return (
    <div>
      <Link href='#' onClick={onToggle}>{id}</Link>
      {open && (
        <Table size="small" className={classes.table}>
          <TableBody>
            <TableRow>
              <TableCell>Download</TableCell>
              <TableCell>
                <Link href={download_url} download>Click to download</Link>
              </TableCell>
            </TableRow>
            <TableRow>
              <TableCell>BuildID</TableCell>
              <TableCell>{buildid}</TableCell>
            </TableRow>
            <TableRow>
              <TableCell>MD5</TableCell>
              <TableCell>{md5}</TableCell>
            </TableRow>
            {symbolRows}
          </TableBody>
        </Table>
      )}
    </div>
  );
}

function App() {
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState(null);

  const onSearch = (data) => {
    setLoading(true);
    (async () => {
      try {
        setResults(await api('/find', data));
      } finally {
        setLoading(false);
      }
    })();
  };

  return (
    <div className="App">
      <p>Powered by the <Link href="https://github.com/niklasb/libc-database/tree/master/searchengine">libc-database search API</Link></p>

      <Grid container spacing={2}>
        <Grid item xs={6} sm={6}>
          <h2>Search</h2>
          <SearchForm onSearch={onSearch} />
        </Grid>
        <Grid item xs={6} sm={6}>
          <h2>Results</h2>
          {loading && <CircularProgress />}
          {results !== null && results.map(x => <Result {...x} />)}
        </Grid>
      </Grid>
    </div>
  );
}

export default App;
