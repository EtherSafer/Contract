const fs = require('fs')
const { exec } = require('child_process')
const path = require('path')
const colors = require('colors')

const WEB_PROJ_SRC_ROOT = path.join(__dirname, "../etherSafer-web/src/ts")
const SERVER_PROJ_SRC_ROOT = path.join(__dirname, "../etherSafer-server/src")

const abiFileTemplate = `\
// tslint:disable:object-literal-key-quotes
export const _name_ = _content_
`

const addressFileTemplate = `\
export const SAFER_CONTRACT_ADDR = '0x_addr_'
export const CREATION_BLOCK = _blocknum_
`

let args = process.argv.slice(2)
let env = 'dev'
for (let arg of args) {
  if (arg !== '--prod' && arg !== '--test') {
    console.log(`Invalid cli arg ${arg} Only valid arg is "--prod"`.error)
    process.exit(1)
  }
  if (arg === '--prod') {
    env = 'prod'
    break
  }
  if (arg === '--test') {
    env = 'test'
    break
  }
}

if (env === 'prod') {
  throw new Error('env --prod is not working properly! copy bytecode from "EtherSafer.json" and paste to myetherwallet.com. see docs/solidityNotes.md')
}

console.log(`Env: ${env.toUpperCase()}`.green)
let command
if (env === 'dev') {
  command = "truffle migrate --reset"
} else if (env === 'test') {
  command = "truffle migrate --reset --network test"
} else {
  command = "truffle migrate --reset --network live"
}
console.log(`Running "${command}"...`.green)

exec(command, (error, stdout, stderror) => {
  if (error) {
    console.error(error)
  }
  console.log("\n============")
  console.log(stdout)
  console.log("============\n")

  const contractAddress = stdout.match(/EtherSafer: 0x([0-9a-f]+)\n/)[1]
  // TODO: get creation block from stdout
  const creationBlock = 0
  console.log('Contract Address:', contractAddress)

  function writeInfoToProject(projectRoot) {
    let addressFile
    if (env === 'prod') {
      addressFile = `${projectRoot}/addresses/mainnet.ts`
    } else if (env === 'test') {
      addressFile = `${projectRoot}/addresses/testnet.ts`
    } else {
      addressFile = `${projectRoot}/addresses/devnet.ts`
    }
    const contents = `export const SAFER_CONTRACT_ADDR = '0x${contractAddress}'\n`
    fs.writeFileSync(
      addressFile, addressFileTemplate
        .replace('_addr_', contractAddress)
        .replace('_blocknum_', creationBlock)
    )
    console.log('Wrote address to', addressFile)

    const saferAbi = JSON.parse(fs.readFileSync(__dirname + "/build/contracts/EtherSafer.json")).abi;
    const saferAbiFile = `${projectRoot}/abi/etherSaferAbi.ts`
    fs.writeFileSync(
      saferAbiFile,
      abiFileTemplate
        .replace('_name_', 'etherSaferAbi')
        .replace('_content_', JSON.stringify(saferAbi, null, 2).replace(/"/g, `'`))
    )
    console.log('Wrote Safer ABI to', saferAbiFile)
  }

  writeInfoToProject(WEB_PROJ_SRC_ROOT)
  writeInfoToProject(SERVER_PROJ_SRC_ROOT)
})
